# Development

This is the contributor-facing guide: how to build it, test it, and find
your way around the source. For how the engine actually works internally
(the comma-disambiguation algorithm, failure folding, the three output
styles, known limitations), see
[docs/HOW_IT_WORKS.md](HOW_IT_WORKS.md).

## Prerequisites

- Swift 5.7 or later (`Package.swift` declares `swift-tools-version:5.7`)
- Xcode or the standalone Swift toolchain -- either works, this is a plain
  Swift Package with no Xcode-project-specific setup

## Build

```bash
git clone https://github.com/woodie/xctidy.git
cd xctidy
swift build            # debug build, for local iteration
swift build -c release # what you'd actually install/ship
```

A `Makefile` wraps the release build for end users -- `make install` builds
and copies the binary to `$(PREFIX)/bin` (`PREFIX` defaults to
`/usr/local`; override with `make install PREFIX=/some/path`). `install`
and `uninstall` only invoke `sudo` when `$(PREFIX)` actually isn't
writable -- the default `/usr/local/bin` is root-owned on Apple Silicon, so
that's a real password prompt rather than a silent failure, but a `PREFIX`
override like `$HOME/.local` never prompts. `make
uninstall`/`make clean`/`make test`/`make xcode` (open the generated Xcode
project) are also available. None of that replaces `swift build`/`swift
test` for day-to-day contributor iteration -- the Makefile is there for the
README's "Build from source" install path.

## Test

```bash
swift test
```

The test target (`XctidyKitTests`) depends on
[Quick](https://github.com/Quick/Quick) and
[Nimble](https://github.com/Quick/Nimble) as test-only dependencies (see
`Package.swift`) -- Swift Package Manager resolves and fetches both
automatically on first build, no separate setup step.

To run a single spec file or narrow down what runs, use Quick's normal
filtering, e.g.:

```bash
swift test --filter EngineSpec
```

## Project layout

```
Sources/
  XctidyKit/
    Engine.swift         matchers, color/style, the Engine class (parsing
                         dispatch + rendering)
    PathSplitting.swift  comma disambiguation: loadKnownAtoms, splitPath
  xctidy/
    main.swift          CLI entry point: arg parsing, reads stdin, prints output
Tests/
  XctidyKitTests/
    EngineSpec.swift           main spec -- loadKnownAtoms, splitPath, Engine
    AnsiColorDemoSpec.swift    a real Quick spec used to produce a genuine
                               comma-flattened name, so the disambiguation
                               logic is tested against real Quick output and
                               not just hand-built fixture strings
docs/
  HOW_IT_WORKS.md       the engine's internals, output styles, limitations
  DEVELOPMENT.md        this file
```

`XctidyKit` is a separate target from the `xctidy` executable specifically
so the test target can `@testable import XctidyKit` without the testability
caveats that come with testing an `.executableTarget` directly.

## Adding or changing a render style

The three styles (default/`-fd`/`-fs`) are the `RenderStyle` enum in
`Sources/XctidyKit/Engine.swift`; per-style leaf/footer behavior lives in
`Engine`'s `renderCase`/`finish()`. If you add a style or change an
existing one:

1. Update `RenderStyle` and the relevant branch in `renderCase`/`finish()`.
2. Add or update its example in `docs/HOW_IT_WORKS.md`'s
   [Output styles](HOW_IT_WORKS.md#output-styles) section -- keep the sample
   output there byte-for-byte accurate, it's the spec for what the style
   should look like.
3. Add coverage in `Tests/XctidyKitTests/EngineSpec.swift` alongside the
   existing per-style tests.
4. Update the flag parsing and usage comment in `Sources/xctidy/main.swift`
   if you're adding a new flag rather than changing an existing style.

## Known limitations to be aware of

Two known gaps are documented in
[docs/HOW_IT_WORKS.md](HOW_IT_WORKS.md#known-limitations) rather than
hidden: `xctidy` only understands Quick/Nimble's `describe`/`context`/`it`
(not Swift Testing's `@Test`/`@Suite` macros), and the tree-rendering dedup
keeps one global "last path," which isn't safe yet under
`xcodebuild -parallel-testing-enabled`'s interleaved destination output.
Both are reasonable starting points if you're looking for something to work
on.

## Releasing

CI exists now (`.github/workflows/makefile.yml`, badge in the README), and
the first tag (`v0.1.0`) is out, but there's still no tap and no Mint
listing.

### Choosing a version number

Tags are `vMAJOR.MINOR.PATCH`, following semver:

- **PATCH** (`v0.1.0` -> `v0.1.1`): bug fixes, doc changes, anything that
  doesn't change `xctidy`'s behavior or CLI surface.
- **MINOR** (`v0.1.0` -> `v0.2.0`): new output style, new flag, new
  capability -- additive, nothing existing breaks.
- **MAJOR**: a breaking CLI change (a flag removed/renamed, a style's output
  format changed in a way a script could depend on). We're starting at
  `0.x` deliberately -- the flag surface (`-fd`/`-fs`/`--format`) only
  settled recently, so nothing is promised stable yet. Move to `1.0.0` once
  that surface has held for a while and breaking it would actually be
  noteworthy.

### Cutting a release

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

then draft a GitHub release from that tag (Releases -> Draft a new release
-> pick the tag). Release notes can stay short -- a "Highlights" list of
what's new/fixed since the last tag is enough; this isn't a project that
needs a formal changelog yet.

## Contributing

Please send a PR. There's no formal style guide; match the conventions
already in `Engine.swift` and keep `docs/HOW_IT_WORKS.md` in sync with any
behavior change -- it's treated as the source of truth for what each output
style should look like, not just descriptive prose.
