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

Every spec file (`LoadKnownAtomsSpec`, `SplitPathSpec`, `EngineSpec`,
`AnsiColorDemoSpec`) is a `QuickSpec` subclass, so SwiftPM's `--filter`
doesn't work on any of them -- `swift test --filter EngineSpec` silently
matches zero tests rather than erroring. `--filter` builds its match list
from statically-declared test methods before running anything, and Quick
generates its test methods dynamically at runtime instead (via XCTest's
`+testInvocations` hook), so none of them ever appear in that list.

You might reach for `fdescribe`/`fcontext`/`fit` next, since Quick's docs
frame those as the way to scope a run. Don't rely on them across files --
when more than one spec file exists in the target, focusing one of them
doesn't reliably skip the others. SwiftPM (unlike Xcode) discovers each
`QuickSpec` subclass's examples lazily, one class at a time, the first
time XCTest asks that class for its test list; each class locks in "run
everything" the moment it's asked, based on whatever's been registered
*so far*. If your focused class happens to be asked after some other
class, that other class already decided to run everything before it ever
saw your focus. This is a real, currently-unfixed Quick bug --
[Quick/Quick#886](https://github.com/Quick/Quick/issues/886) -- not
anything specific to this project. `fdescribe` is still fine *within* a
single file you've already isolated some other way; it's just not a
substitute for scoping the run itself.

The reliable way to scope a run to one spec file needs no source edits at
all: drive the build through `xcodebuild` instead of `swift test`, and
let `-only-testing:` select the class before Quick's focus system ever
gets involved. This works directly against the bare `Package.swift`, no
`.xcodeproj` required (Xcode 11+):

```bash
xcodebuild -list                                      # confirm the scheme name (likely "xctidy")
xcodebuild test -scheme xctidy -destination 'platform=macOS' \
  -only-testing:XctidyKitTests/SplitPathSpec | xctidy Tests/XctidyKitTests
```

`./test.sh` wraps exactly this so you don't have to type it out:

```bash
./test.sh                                  # full run, all specs
./test.sh SplitPathSpec                    # one spec class
./test.sh Tests/XctidyKitTests/SplitPathSpec.swift  # or a tab-completed path
```

It accepts a bare class name, a `.swift` path (tab-completion-friendly), an
already-qualified `Target/Class` filter, or any raw `xcodebuild` flag
(forwarded as-is). The scheme, destination, and test target are
configuration variables at the top of the script -- override via
environment (`SCHEME=... ./test.sh`) if you've adapted it for another
package.

This is also why every spec file here sticks to **one `QuickSpec` class,
one top-level `describe`** -- the file's class name is all you need to
isolate it with `-only-testing:`, no hunting through the file for what to
focus. See the README's [Writing tests](../README.md#writing-tests)
section for the full convention, and
`Tests/XctidyKitTests/SplitPathSpec.swift` for as plain an example as it
gets.

## Project layout

```
Sources/
  XctidyKit/
    Engine.swift         matchers, color/style, the Engine class (parsing
                         dispatch + rendering)
    PathSplitting.swift  comma disambiguation: loadKnownAtoms, splitPath
    VersionFlag.swift    wantsVersion -- detects --version/-v, pulled out of
                         main.swift so it's unit-testable
  xctidy/
    main.swift          CLI entry point: arg parsing, reads stdin, prints output
    Version.swift        xctidyVersion constant -- generated by `make
                         version`/`make build` from the nearest git tag, not
                         hand-edited (committed placeholder is "dev")
Tests/
  XctidyKitTests/
    LoadKnownAtomsSpec.swift   loadKnownAtoms, with its own fixtures
    SplitPathSpec.swift        splitPath, fixture-free (inline literals only)
    EngineSpec.swift           the Engine class: tree rendering, noise
                               suppression, color output, and all three
                               render styles
    AnsiColorDemoSpec.swift    a real Quick spec used to produce a genuine
                               comma-flattened name, so the disambiguation
                               logic is tested against real Quick output and
                               not just hand-built fixture strings
    VersionFlagSpec.swift      wantsVersion: long/short flag, position
                               independence, non-matches
docs/
  HOW_IT_WORKS.md       the engine's internals, output styles, limitations
  DEVELOPMENT.md        this file
test.sh                 wraps the xcodebuild -only-testing: dance above so
                        you can run one spec file without typing it out
```

Each file above is one `QuickSpec` class with exactly one top-level
`describe`, matching the file's name and subject -- see "Writing tests" in
the README for why that convention matters if you're adding a new spec.

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
