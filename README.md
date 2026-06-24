# xctidy

[![Swift](https://img.shields.io/badge/swift-5.7%2B-F05138.svg)](Package.swift)
[![CI](https://github.com/woodie/xctidy/actions/workflows/makefile.yml/badge.svg)](https://github.com/woodie/xctidy/actions/workflows/makefile.yml)
[![Release](https://img.shields.io/github/v/release/woodie/xctidy.svg)](https://github.com/woodie/xctidy/releases/latest)
[![License](https://img.shields.io/github/license/woodie/xctidy.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/woodie/xctidy.svg)](https://github.com/woodie/xctidy/releases/latest)

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
swift test | xctidy Tests
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
    xcodebuild_formatter: "/usr/local/bin/xctidy -fd Tests"
  )
end
```

## Output styles

Three named styles, each matching a convention from a familiar test runner.
All three end with the same xcbeautify-style footer.

| Flag | Convention | Look |
|---|---|---|
|   | Our base formatter | Glyph + `name (N seconds)`, failures add `(FAILED - N)` |
| -fd | RSpec's doc format | Plain colored name, yellow `(PENDING)` for skips |
| -fs | Mocha's spec format | Green `✔` + gray name, red `✗ name (FAILED - N)` |

The screenshot above is `-fd`. Full samples of all three styles:
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
