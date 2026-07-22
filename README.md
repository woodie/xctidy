# xctidy

[![Swift](https://img.shields.io/badge/swift-5.7%2B-F05138.svg)](Package.swift)
[![CI](https://github.com/woodie/xctidy/actions/workflows/makefile.yml/badge.svg)](https://github.com/woodie/xctidy/actions/workflows/makefile.yml)
[![Release](https://img.shields.io/github/v/release/woodie/xctidy.svg)](https://github.com/woodie/xctidy/releases/latest)
[![License](https://img.shields.io/github/license/woodie/xctidy.svg)](LICENSE)

![Example Screenshot](docs/example.png)


**`xctidy` adds nested describe/context/it tree support to `xcodebuild`.**

An alternative to xcbeautify and xcpretty written in Swift.

## Features

- Test output is more concise and readable
- Familiar output conventions from RSpec and Mocha
- Drop-in `xcodebuild_formatter` for fastlane's `scan`/`gym`/`snapshot`
- Written in Swift and compiles to a static binary

## Installation

### Build from source

```bash
git clone https://github.com/woodie/xctidy.git
cd xctidy
make install
```

## Usage

```bash
xcodebuild test [flags] | xctidy Tests
```

`xctidy` itself exits 1 if any test case it rendered failed, so a plain
`... | xctidy Tests` already reports a real test failure correctly. It
can't know about a failure further upstream, though -- if `xcodebuild`/
`swift test` itself fails before any test case ever runs (a build error,
a crashed test host), that never produces a "Test Case ... failed" line
for `xctidy` to see. For that case, also propagate the upstream tool's
own exit status (e.g. on CI):

```bash
set -o pipefail && xcodebuild test [flags] | xctidy Tests
```

```bash
swift test 2>&1 | xctidy Tests
```

Note the `2>&1` here -- unlike `xcodebuild`, which already merges the test
runner's output into its own stdout, `swift test` execs the XCTest runner
directly and inherits its file descriptors unmerged. On macOS, XCTest's
`Test Suite`/`Test Case` status lines go to stderr, not stdout, so without
`2>&1` `xctidy` only ever sees the build phase's own output and nothing to
render.

The positional argument (`Tests` above) is the path to your specs
directory -- it's how `xctidy` cross-references `describe`/`context`/`it`
string literals to disambiguate comma-flattened names. Omit it and `xctidy`
falls back to a heuristic that handles most cases, but a known spec
directory is more reliable.

### fastlane

`scan` (and `gym`/`snapshot`) already hand this exact pipeline slot to
xcbeautify/xcpretty via the `xcodebuild_formatter` option -- swap the value,
no new stage needed:

```ruby
# Fastfile
lane :test do
  scan(
    scheme: "MyApp",
    xcodebuild_formatter: "/usr/local/bin/xctidy -fd Tests"
  )
end
```

### Version

```bash
xctidy --version
```

Prints the installed version and exits -- bare number, no `xctidy`/`v`
prefix (matches xcbeautify's `--version` style). Derived from the nearest
git tag at build time (see the Makefile's `version` target), so it always
reflects what you actually installed, not a hand-maintained constant.

## Output styles

Four named styles, each matching a convention from a familiar test runner.
The first three end with the same xcbeautify-style footer; `-fv` ends with
Vitest's own footer shape instead.

| Flag | Convention | Look |
|---|---|---|
|   | Our base formatter | Glyph + `name (N seconds)`, failures add `(FAILED - N)` |
| -fd | RSpec's doc format | Plain colored name, yellow `(PENDING)` for skips |
| -fs | Mocha's spec format | Green `✔` + gray name, red `✗ name (FAILED - N)` |
| -fv | Vitest's own tree | Green `✓ name`, two-toned green `2ms`, red `× name`, dim gray `↓ name` |

`-fv` is [`gorderly`](https://github.com/woodie/gorderly)'s `-fv` counterpart
for the XCTest side -- same glyphs, same millisecond conversion, same
`Tests`/`Duration` footer shape. It currently omits Vitest's `Test Files`
line: XCTest's own Test Suite nesting (a per-class suite wrapped in an "All
tests"/"Selected tests" aggregate suite) hasn't been verified against real
`xcodebuild` output, so a suite-level pass/fail count risks over-counting
the wrapper suites as if they were their own files. `gorderly`'s equivalent
(one line per Go package) had no such ambiguity.

The screenshot above is `-fd`. Full samples of all three xcbeautify-style
styles: [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md#output-styles).

## Writing tests

`xctidy` renders whatever nesting your test framework produces, so the
nesting it shows is only as good as how you write your specs. If you're
using [Quick](https://github.com/Quick/Quick)/[Nimble](https://github.com/Quick/Nimble)
(the `describe`/`context`/`it` style), keep to **one `QuickSpec` class per
file, one top-level `describe` per file, matching the file's subject** --
see [`Tests/XctidyKitTests/SplitPathSpec.swift`](Tests/XctidyKitTests/SplitPathSpec.swift)
for a minimal example. It keeps the rendered tree predictable (one root
per file) and keeps `-only-testing:` selection a one-line lookup instead
of a multi-file hunt (see `docs/DEVELOPMENT.md`'s
[Test](docs/DEVELOPMENT.md#test) section for why `swift test --filter`
doesn't work with Quick and what to use instead).

For how we structure what's *inside* a spec -- nesting context so it's
available to sub-tests, mocking and stubbing -- see
[docs/FRAMEWORK.md](docs/FRAMEWORK.md), shared with
[`zouk`](https://github.com/woodie/zouk) and
[`next-caltrain-swift`](https://github.com/woodie/next-caltrain-swift).

## Development

```
make build    # swift build --configuration release
make install  # builds, then copies the binary to $(PREFIX)/bin (default /usr/local)
make test     # verbose, dogfoods xctidy on its own suite (swift test | xctidy)
make lint     # swiftlint lint --strict
make check    # terse: silent on success, full log on failure
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for project layout, how to
add a render style, the release process, and the rest of the Makefile
(`uninstall`, `clean`, `xcode`). See
[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) for how the comma
disambiguation and failure folding actually work, and for known limitations.
