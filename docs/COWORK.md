# Working with xctidy

Cross-project conventions (git locks, sandbox toolchain) are in
`~/workspace/woodie/docs/COWORK.md`.

## What this is

A standalone Swift CLI that parses raw `xcodebuild test`/`swift test` output
directly -- the same textual protocol xcpretty/xcbeautify regex-match -- into a
nested `describe`/`context`/`it` tree. A drop-in fastlane `xcodebuild_formatter`
replacement for xcbeautify/xcpretty, not a post-processor chained after either.

## Architecture

- `Sources/XctidyKit/Engine.swift` -- core engine. `Matchers` mirrors xcpretty's own
  regexes. `loadKnownAtoms`/`splitPath` disambiguate comma-joined Quick/Nimble names
  via a dictionary of known atoms scanned from the specs directory, falling back to a
  paren-depth heuristic when no atoms are found. `Engine` is the stateful
  line-by-line renderer; `RenderStyle` controls output style.
- `Sources/xctidy/main.swift` -- CLI entry point. Reads stdin, feeds `Engine`, prints
  `engine.finish()`.
- `docs/HOW_IT_WORKS.md` -- the comma problem, failure folding, output styles, and
  fastlane integration. Read before touching `RenderStyle`/`renderCase`/`finish()`.
- `docs/DEVELOPMENT.md` -- contributor-facing build/test/release guide.

## Design decisions worth knowing

- **`loadKnownAtoms` scans recursively** (`subpathsOfDirectory`, not
  `contentsOfDirectory`) -- SwiftPM puts each target's specs one level below the
  directory a caller passes (`Tests/<Module>Tests/*.swift`, never directly inside
  `Tests/`). A non-recursive scan silently finds zero atoms for the exact invocation
  the README recommends, which drops every name to the heuristic fallback and
  mis-splits bare-prose-comma descriptions. Real regression, fixed -- don't revert to
  a non-recursive scan.
- **CLI surface is intentionally narrow**: `-fd`, `-fs`, `--format
  documentation|spec`, and the default (no flag, classic). The old long boolean
  flags (`--classic`/`--fd`/`--spec`/`--style`) were removed by request -- don't
  re-add them without being asked.
- **`xctidy` exits 1 on a rendered test failure** (`v0.4.0`).
- **`xctidy` only reads stdin** -- `swift build`/`swift test`'s own build-progress
  lines go to stderr, so `swift test | xctidy Tests` (no `2>&1`) is already clean on
  its own; `Engine.swift`'s noise suppression is default-deny regardless of whether
  stderr is merged in.
- **`make install` auto-elevates via a computed `$(SUDO)` Makefile variable** --
  walks up to the nearest *existing* ancestor of `$(PREFIX)/bin` and only falls back
  to `sudo` if that ancestor isn't writable (handles a not-yet-created `PREFIX` like
  `$HOME/.local` correctly).
- **CI-only Swift type-checker timeouts are a real, recurring risk** for large Quick
  spec files with multiple back-to-back `expect(...).to(equal(...))` calls in one
  `it` -- a local `swift test` pass does not guarantee CI's toolchain won't time out
  on the same code. If it recurs: isolate the dense block into its own file/
  `QuickSpec` subclass, pre-resolve values into type-annotated `let`s before the
  `expect` calls, and prefer literal constants over compound arithmetic.

## Testing

Quick/Nimble, dogfooding the tool's own headline feature (real comma-flattened Quick
names). `EngineSpec.swift` is the main spec; `AnsiColorDemoSpec.swift` and
`DistanceInTimeBoundarySpec`-style isolated files cover the trickier disambiguation
and CI-timeout-prone cases respectively.

## Sandbox limitation

No Swift toolchain here -- `Sources/`/`Tests/` are edited by inspection, verified via
`swift build`/`swift test`/`make check` on the user's own Mac. The sandbox also can't
unlink files inside the mounted workspace folder directly; use `allow_cowork_file_delete`
(see the cross-project doc's "Git lock files" section) rather than handing off a
manual `rm`/`git rm` for the user to run.

## Current status

`v0.4.0`, CI green (macOS/Swift 5.10). Output parity-audited against `gorderly` in
both directions.
