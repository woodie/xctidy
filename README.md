# xctidy

[![Swift](https://img.shields.io/badge/swift-5.7%2B-F05138.svg)](Package.swift)
[![License](https://img.shields.io/github/license/woodie/xctidy.svg)](LICENSE)

<!-- CI and release badges land here once a GitHub Actions workflow and a tagged release exist. -->

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

If you want `xctidy` to exit with the same status code as `xcodebuild` (e.g.
on CI):

```bash
set -o pipefail && xcodebuild test [flags] | xctidy Tests
```

```bash
swift test 2>&1 | xctidy Tests
```

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
    xcodebuild_formatter: "/usr/local/bin/xctidy --fd Tests"
  )
end
```

## Output styles

Three named styles, each matching a convention from some other test runner
you've probably already seen:

| Flag | Short form | Convention | Look |
|---|---|---|---|
|   |   | Our base formatter | glyph + `name (N seconds)`, failures add `(FAILED - N)` |
| `--fd` | `-fd` | RSpec's format documentation | plain colored name, yellow `(PENDING)` for skips |
| `--spec` | `-fs` | Mocha's default reporter | green `✔` + gray name, red `✗ name (FAILED - N)` |

All three end with the exact same closing footer, byte-for-byte, lifted
from real xcbeautify: a green `Test Succeeded`/red `Test Failed` headline,
then `Tests Passed: X failed, Y skipped, Z total (N seconds)`. `--fd` and
`--spec` only change how the tree above that footer looks (RSpec's/Mocha's
own native run summary isn't printed on top of it) -- one shared, unambiguous
ending regardless of style.

Each style is also reachable through `--format <name>` (`documentation`,
`spec`, `classic`) or, for the two non-default styles, its short form --
the `-f<letter>` idiom RSpec itself uses, since `rspec -fd` is really `-f`
(`--format`) immediately followed by the formatter's single-letter code,
not a dedicated two-letter flag. Classic has no short form -- it's already
what you get with no flag at all, so a `-fc` that just reproduced default
behavior would only confuse people about what it's for. `--style <name>`
(with `fd` in place of `documentation`) still works too -- pick whichever
reads best in your pipeline.

The screenshot above is `--fd` -- real `swift test` output from this
project's own `EngineSpec.swift` suite, piped through that style. Full text
samples of all three styles:
[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md#output-styles).

## Development

```bash
swift build
swift test
```

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for project layout, how to
add a render style, and the release process. See
[docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md) for how the comma
disambiguation and failure folding actually work, and for known limitations.

## Contributing

Please send a PR! [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) covers getting
set up.

## License

MIT, see [LICENSE](LICENSE).
