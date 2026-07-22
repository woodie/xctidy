# Comments

Rationale, history, and design notes that used to live as multi-line
comments in the source. Organized by file, then by the type, property, or
function each note is attached to. The source itself now carries at most
one short line at any given spot -- anything longer that would previously
have been a `///` doc comment or a multi-line `//` note lives here instead.
When a code location kept its own one-line comment, it's noted below so
this stays a complete map of "why," not a duplicate of what's already
readable in the file.

## Package.swift

### `dependencies`, Quick/Nimble comment
Kept a one-line comment in place: "Test-only: lets one spec be a *real*
Quick describe/context/it spec so swift test produces a genuine
comma-flattened name to disambiguate, not just a hand-built fixture."

Full history: Quick and Nimble are pulled in as test-only dependencies
specifically so `AnsiColorDemoSpec` (see its own note below) can be a real,
live Quick spec rather than a hand-typed fixture string -- when `swift
test` runs it, XCTest reports back a genuinely comma-flattened selector
name, the same shape any real Quick/Nimble project produces, so the
comma-disambiguation logic under test is exercised against authentic
input, not something built to look like it.

### `.target(name: "XctidyKit")`
Kept a one-line comment in place: "Own target so the test target can
@testable import it without .executableTarget's testability caveats."

Full history: the core engine (parsing + rendering) lives in its own
library target, separate from the `xctidy` executable target, specifically
so `XctidyKitTests` can `@testable import XctidyKit` cleanly. Testing an
`.executableTarget` directly comes with its own testability caveats in
SwiftPM; splitting the engine out avoids all of them.

## Sources/XctidyKit/Engine.swift

### Engine.swift (file header)
No comment kept in source; redundant with `PathSplitting.swift`'s own
header and the `RenderStyle` doc comment below, so it added nothing a
reader wouldn't already get from either.

History: `Engine.swift` parses raw `xcodebuild test` output directly --
the same textual protocol xcpretty's `parser.rb` and xcbeautify both
regex-match (there's no formal API; this *is* the API), so no
xcbeautify/xcpretty installation is required. The reason this matters:
Quick promotes the full comma-joined `describe`/`context`/`it` text
(literal prose, commas and all) to be the XCTest selector name, so a raw
`Test Case '-[Class full, prose, name]'` line can't just be split on every
comma -- some commas are nesting separators between description levels,
some are just commas that happen to appear in the prose itself. The engine
resolves that ambiguity by cross-referencing the literal
`describe(...)`/`context(...)`/`it(...)` string literals found in the
project's own `.swift` files under `Tests/` (see `loadKnownAtoms` in
`PathSplitting.swift`), falling back to a paren-depth-aware heuristic
split only when that dictionary lookup can't resolve a name uniquely.

### `Matchers` (enum)
Kept a one-line comment in place: "caseStarted/caseFinished's class
capture uses \S+ (not xcpretty's ambiguous (.*) (.*)) -- class names never
contain spaces."

Full history: `Matchers` mirrors xcpretty's own `parser.rb` regexes line
for line, with one deliberate improvement: the suite/class capture group
in `caseStarted`/`caseFinished` uses `\S+` (no whitespace) instead of
xcpretty's ambiguous `(.*) (.*)`, since Swift/Obj-C class names never
contain spaces. That cleanly separates "ClassName" from "full prose
comma-joined name" in one regex pass -- xcpretty's own pattern just
greedily grabs everything as a flat string, which is fine for its flat
failure list but unusable as input to a nested tree.

### `RenderStyle` (enum)
Kept a one-line comment in place: "Controls per-leaf label rendering:
.classic (default, glyph + time), .doc (RSpec -fd clone), .spec
(Mocha/Jest clone). All three share one identical xcbeautify-style closing
footer; see docs/COMMENTS.md for the full styles/footer rationale."

Full history: `.classic` (the default) is the look xctidy's original
prototype had -- every leaf gets xcbeautify's own "✔"/"⊘"/"✖" glyph plus
the per-test "(N seconds)" xcodebuild reports, both colored
(green/cyan/red); a failed leaf additionally keeps this project's own
"(FAILED - N)" cross-reference into the closing Failures section (see
`docs/HOW_IT_WORKS.md`, "Failure folding"). `.doc` clones real RSpec's
`-fd`/documentation formatter's *leaf* rendering only: a plain colored
name with no glyph and no per-test time, and pending examples render
yellow with RSpec's own wording, "(PENDING)" -- not Xcode's "SKIPPED".
`.spec` clones the more common convention used by reporters like Mocha's
default `spec` reporter or Jest, again leaf-rendering only: a green "✔"
with the passing test's name dimmed to gray (de-emphasized, since passes
aren't where attention is needed), a red "✗ name (FAILED - N)" for
failures, and a cyan "- name (SKIPPED)" for skips.

All three styles end with exactly the same thing: real xcbeautify's own
run-results footer -- a green "Test Succeeded" (or red "Test Failed")
headline, then "Tests Passed: X failed, Y skipped, Z total (N seconds)".
`.doc` and `.spec` deliberately don't additionally print RSpec's/Mocha's
own native run summary ("Finished in.../X examples", "N passing (Ttime)")
on top of that footer -- an earlier version of this tool stacked that
native summary before the xcbeautify footer, but seeing all three styles'
real output side by side made that look like three different conventions
for the same information instead of one shared, unambiguous ending. See
`finish()`'s trailing `if exampleCount > 0` block, below.

### `Engine.feedLine(_:)`
Kept a one-line comment in place: "Feeds one raw xcodebuild test output
line; suppresses routine build-phase noise but passes through anything
containing "error:" or a build-failure marker verbatim."

Full history: lines that are part of the test protocol are consumed and
re-rendered as the nested tree; everything else (compiles, links,
codesign -- the build-phase noise xcpretty/xcbeautify spend most of their
matchers on) is suppressed, *except* for anything containing "error:" or
a fatal/build-failed marker, which is passed through verbatim so a real
build failure is never silently hidden. This tool is scoped to test
output only, the same way ginkgo-fd doesn't bother reformatting `go
build`'s own output.

### `Engine.feedLine(_:)`, `caseFinished` branch, `time` local
Kept a one-line comment in place: "group(4) is the per-test time; only
.classic renders it per-leaf (see labelForPassed/labelForSkipped/
labelForFailed)."

Full history: `group(4)` is the per-test "(N seconds)" xcodebuild reports
for every case regardless of outcome. `.classic` surfaces it directly per
leaf (see the `RenderStyle` doc comment above); `.doc`/`.spec` don't use
it per-leaf at all, only `lastTestTimeText`'s run-level total in
`finish()`.

### `Engine.feedLine(_:)`, `executedSummary` branch
Kept a one-line comment in place: "Last executedSummary line wins --
XCTest finishes inner scopes before outer ones, so the final match is
always the outermost total."

Full history: this line is suppressed from passthrough either way; the
captured time is kept only for the shared closing footer's "(N seconds)"
annotation in `finish()`, regardless of style. There's one
`executedSummary` line per nesting level (per-class, per-bundle, "All
tests") in a real `xcodebuild test` run -- the last one wins, which is
always the outermost/final total since XCTest finishes inner scopes
before outer ones.

### `Engine.timedSuffix(_:_:)`
Kept a one-line comment in place: "`.classic`'s "(N seconds)" suffix,
colored to match its glyph -- mirrors xcbeautify's own `.coloredTime()`."

### `Engine.labelForSkipped(name:time:)`, `.classic` case
Kept a one-line comment in place: "classic signals skips by glyph (⊘) +
color only, not text -- see -fd/-fs for spelled-out "(SKIPPED)"/
"(PENDING)" labels."

Full history: no "(SKIPPED)" text suffix appears here, deliberately --
`.classic` distinguishes skips from passes by glyph (⊘ vs ✔) and color
alone. `-fd` and `-fs` both spell it out in words instead; reach for one
of those if a glyph-only signal isn't enough in a given terminal/font.

### `Engine.labelForFailed(name:path:time:)`, `.classic` case
Kept a one-line comment in place: "Keeps the "(FAILED - N)" Failures
cross-reference alongside the original glyph + per-test time."

Full history: `.classic` keeps the "(FAILED - N)" Failures-section
cross-reference -- the headline improvement that reading raw `xcodebuild`
protocol directly (rather than xcbeautify's already-flattened text) makes
possible -- alongside the original prototype's glyph and per-test time.

### `Engine.finish()`, `if exampleCount > 0` block
Kept a one-line comment in place: "Gated on exampleCount > 0 so
noise-only input still finishes as just "\n", matching xcodebuild's own
behavior of only printing "** TEST SUCCEEDED **" after a real test run."

Full history: this block prints real xcbeautify's own run-results footer,
lifted verbatim from a genuine `xcodebuild test` run. It's the *only* run
summary any style prints -- `.doc` and `.spec` render their leaves
differently (see the `RenderStyle` doc comment above) but don't get their
own native RSpec-/Mocha-style run summary on top of it, so there's exactly
one footer convention to read regardless of which style produced the tree
above it. It's a green/red headline followed by a "Tests Passed:" line
that -- despite the name -- always lists all three counts, not just
passes. The whole block is gated on `exampleCount > 0` so that noise-only
input (no `Test Case` lines at all) still finishes as just `"\n"`,
matching xcodebuild's own behavior: it only ever prints "** TEST SUCCEEDED
**" when a test run actually happened, never on a noise-only or
build-only invocation.

## Sources/XctidyKit/PathSplitting.swift

### PathSplitting.swift (file header) / `// MARK: - Dictionary-based comma disambiguation`
Kept a one-line comment in place: "Builds the atom set from spec files,
then tries to decompose a flattened Quick name into a unique ", "-joined
sequence of atoms, falling back to a heuristic split if ambiguous."

Full history: builds a set of every known describe/context/it literal
string by scanning the project's spec files, then tries to decompose a
flattened Quick name into a `", "`-joined sequence of those known atoms.
The code only needs to know whether there is exactly one way to do that
(unambiguous) or not (fall back to the heuristic) -- so
`findDecompositions` stops searching after finding 2 decompositions
rather than enumerating every possibility. This file was split out of
`Engine.swift`: this half is pure parsing/decomposition with no
dependency on `Engine`'s rendering state, only on `Matchers.atomCall`
(still defined in `Engine.swift`, referenced here across files in the
same module, so no import is needed).

### `loadKnownAtoms(specsDir:)`
Kept a one-line comment in place: "Recursively scans every `*.swift` file
under `specsDir` for describe/context/it string literals; must be
recursive since SwiftPM nests each target's specs one level below
`Tests/`."

Full history: this used to be a non-recursive `contentsOfDirectory(atPath:)`
glob, carried over directly from xctidy's own brief original Python
prototype's `Path(specs_dir).glob("*.swift")`. That was wrong for the
layout this tool's own README tells people to use: `xcodebuild test |
xctidy Tests` (or `swift test 2>&1 | xctidy Tests`) passes the top-level
`Tests` directory, but SwiftPM puts each target's specs one level below
that, in `Tests/<ModuleName>Tests/*.swift` -- never directly inside
`Tests/` itself. A non-recursive glob over `Tests/` therefore found
nothing there, so `atoms` came back empty for the exact invocation the
README recommends, which silently dropped every name to the
paren-depth-only heuristic in `splitPath` -- and that heuristic mis-splits
a bare prose comma with no parentheses around it (e.g. "decodes the name,
size, time, and url" got split into four spurious nested levels).

This was found by converting a separate sibling project (`zouk`) to
Quick/Nimble, then piping its real `make test` output through `xctidy`
and getting back a mis-rendered tree full of spurious extra nesting at
every bare prose comma -- even though the dictionary-disambiguation
algorithm itself was never broken, and `AnsiColorDemoSpec.swift` already
had a passing test proving it handles exactly this kind of case. The root
cause traced back to `loadKnownAtoms` never finding any atoms in the
first place for a realistic `Tests/<ModuleName>Tests/` layout, since
every prior test covering it wrote fixtures directly inside a flat temp
directory. Fixed by switching to `subpathsOfDirectory(atPath:)`, which
walks the whole tree under `specsDir` rather than just its immediate
children, so `xctidy Tests` now actually finds every spec file regardless
of how many target subdirectories sit underneath it.
`LoadKnownAtomsSpec.swift`'s "recurses into per-target subdirectories like
Tests/<ModuleName>Tests/" case (see its own note below) is the regression
test that would have caught this before it ever reached a real project.

### `splitHeuristic(_:)`
Kept a one-line comment in place: "Splits only at top-level (paren-depth
0) ", "; keeps parenthetical asides like "(San Francisco to San Jose
Diridon)" intact."

Full history: this is the fallback path used when the atom dictionary is
empty or can't disambiguate a name uniquely.

## Sources/XctidyKit/VersionFlag.swift

### VersionFlag.swift (file header)
Kept a one-line comment in place: "Pulled out of main.swift so it's
unit-testable -- main.swift's top-level script code isn't reachable from
XctidyKitTests; see VersionFlagSpec."

Full history: `--version`/`-v` detection lives here rather than inline in
`main.swift` specifically so it's unit-testable like the rest of the
argument-handling surface in `XctidyKit` -- `main.swift` itself is an
executable target's top-level script code, which `XctidyKitTests` can't
reach via `@testable import`.

### `wantsVersion(_:)`
Kept a one-line comment in place: "Whether `args` requests version
reporting; must be checked before the stdin-reading loop starts, or a
bare `xctidy --version` would hang waiting for piped input that never
arrives."

Full history: `main.swift` checks this before its stdin-reading loop
starts. It must short-circuit immediately rather than fall through to
`readLine()`, which would otherwise hang waiting for piped input that
will never arrive when someone just runs `xctidy --version` directly from
a terminal with nothing piped in.

## Sources/xctidy/main.swift

### File header / usage comment
Kept a one-line comment in place: "Usage: xcodebuild test ... | xctidy
[-fd|-fs|--format documentation|--format spec] [path-to-Tests-dir]"

Full history: reads raw xcodebuild output from stdin -- the same protocol
xcpretty and xcbeautify both parse -- and writes a nested tree to stdout.
No xcbeautify/xcpretty installation is required; xctidy is a drop-in
replacement formatter, not a post-processor chained after either of them
(see `docs/HOW_IT_WORKS.md`, "Where this fits in a fastlane pipeline").

Flag reference: `(no flag)` is the default -- glyph + "name (N seconds)"
per leaf ("✔"/"⊘"/"✖", colored), with failures additionally keeping
"(FAILED - N)". `-fd` is an actual clone of real RSpec's
`-fd`/documentation formatter's leaf rendering: plain colored name, no
glyph, no per-test time; pending examples are yellow and say "(PENDING)".
Long form: `--format documentation`. `-fs` is the more common look --
green "✔ name" (name dimmed gray) for passes, red "✗ name (FAILED - 1)"
for failures, cyan "- name (SKIPPED)" for skips, the same convention as
Mocha's default `spec` reporter or Jest's. Long form: `--format spec`.
`-v` prints the version and exits with no stdin read; long form
`--version`. It prints a bare number, no "xctidy" prefix or "v", matching
xcbeautify's own `--version` output style.

All three styles end with the exact same run-results footer, lifted
verbatim from real xcbeautify -- a green "Test Succeeded"/red "Test
Failed" headline, then "Tests Passed: X failed, Y skipped, Z total (N
seconds)". Neither `-fd` nor `-fs` additionally prints RSpec's/Mocha's own
native run summary on top of that -- see `docs/HOW_IT_WORKS.md`, "Output
styles".

### `wantsVersion(args)` check
Kept a one-line comment in place: "Checked before the stdin-reading loop,
not as a switch case; see wantsVersion's doc comment for why."

Full history: checked before the stdin-reading loop below, not handled as
a case inside the flag-parsing switch -- see `wantsVersion`'s doc comment
(`XctidyKit/VersionFlag.swift`) for why this must short-circuit
immediately rather than fall through to `readLine()`.

### Final `exit(engine.failures.isEmpty ? 0 : 1)`
Kept a short comment in place explaining the mirror to `gorderly`'s
`main.go`.

Full history: before this, `main.swift` always exited 0 here regardless
of `engine.failures` -- the only non-zero exits were flag-parsing errors
(an unrecognized `--format` value). That meant a bare
`xcodebuild test | xctidy Tests` (no `set -o pipefail`) reported success
even when real tests failed, since the pipeline's exit status defaulted
to the last command's (xctidy's, always 0). The README already warned
about this for `xcodebuild`/`swift test` piping, but the fix was always
on the caller (`set -o pipefail`), never in `xctidy` itself. Found while
reviewing whether xctidy's own `test` Makefile target could safely pipe
`swift test` through `xctidy` for prettier dogfooded output the way
`gorderly`'s `test: go run . -fd ./...` does -- `gorderly`'s `main.go`
already does the equivalent (`if failed > 0 { return 1 }`), which is
exactly why gorderly's self-piped target needed no such workaround.
Bringing xctidy in line with that fixes the general case, not just the
Makefile: every documented usage (README, fastlane's
`xcodebuild_formatter`) now gets a meaningful exit code by default.

This isn't a full substitute for `set -o pipefail`, though: it only
reflects failures `engine` actually saw as rendered test-case lines. If
`xcodebuild`/`swift test` fails before any test runs at all (a build
error, a crashed test host), no "Test Case ... failed" line is ever fed
in, so `engine.failures` stays empty even though the run genuinely
failed. `set -o pipefail` (or checking `${PIPESTATUS[0]}`) is still the
only way to catch that upstream case -- see the README's Usage section.

## Sources/xctidy/Version.swift

### `xctidyVersion`
Kept a one-line comment in place: "Generated by `make version` -- do not
hand-edit or commit changes (see Makefile); committed placeholder value
is "dev"."

## Tests/XctidyKitTests/AnsiColorDemoSpec.swift

### `AnsiColorDemoSpec` (class)
Kept a one-line comment in place: "A *real* Quick spec (not a fixture
string) whose second `it`'s bare prose comma ("red, not yellow") only
atom-dictionary disambiguation resolves correctly."

Full history: this is a *real* Quick spec, not a hand-built fixture
string, so `swift test` emits a genuine comma-flattened XCTest name, the
same kind any Quick/Nimble project produces. Pipe it through to see the
tree: `swift test 2>&1 | .build/release/xctidy Tests/XctidyKitTests`. The
second `it` has a bare prose comma ("red, not yellow") that sits
*outside* any parentheses -- the paren-depth heuristic alone would
mis-split that into a 4th tree level. Only the atom-dictionary
disambiguation, cross-referencing this file's own describe/context/it
literals, resolves it correctly, which is the actual point of this demo.

## Tests/XctidyKitTests/EngineSpec.swift

### `EngineSpec` (class)
No comment kept in source; the one-QuickSpec-class-per-file convention is
already fully documented in `docs/DEVELOPMENT.md`'s "Test" section and
the README's "Writing tests" section, so restating it here in every spec
file was pure duplication.

History: one `QuickSpec` class per file, one top-level `describe` per
file, matching the file's subject (here, the `Engine` class itself).

### `describe("Engine")` -> "renders a deduped nested tree for passing cases" -> shared-prefix assertion
No comment kept in source; judged self-explanatory given the surrounding
assertions.

History: distinguishes the second (shorter) leaf from the first by its
own elapsed time, now that `.classic` appends "(N seconds)" to every
leaf.

### `describe("Engine")` -> "annotates a skipped case"
No comment kept in source; the "classic style" context lower in the same
file (and `Engine.labelForSkipped`'s own kept comment) already covers
this.

History: `.classic` distinguishes skips from passes by glyph + color, not
text -- see "classic style" below for why there's no "(SKIPPED)" suffix
in this assertion.

## Tests/XctidyKitTests/LoadKnownAtomsSpec.swift

### `// MARK: - Fixtures` comment, `goodTimesSwift`/`caltrainServiceSwift`
Kept a one-line comment in place: "Real chains from next-caltrain-swift's
Tests/, proving both disambiguation edge cases: a parenthetical aside and
a bare prose comma with no parens."

Full history: both fixture strings are real chains pulled from
`next-caltrain-swift`'s `.swift` files under `Tests/`, used to prove both
known comma-disambiguation edge cases: a parenthetical aside, and a bare
prose comma with no parens at all.

### `LoadKnownAtomsSpec` (class)
No comment kept in source; same reasoning as `EngineSpec` above --
duplicates `docs/DEVELOPMENT.md`'s "Test" section.

History: one `QuickSpec` class per file, one top-level `describe` per
file, matching the file's subject (here, `loadKnownAtoms` from
`PathSplitting.swift`). This is the shape new specs in this project --
and in any project using xctidy -- should follow: it's what makes a
single file isolatable by class name with `-only-testing:`, no hunting
for what to focus.

### `describe("loadKnownAtoms")` -> "recurses into per-target subdirectories like Tests/<ModuleName>Tests/"
Kept a one-line comment in place: "Regression test for the
non-recursive-glob bug: SwiftPM nests specs one level under Tests/, e.g.
Tests/FooKitTests/; see docs/COMMENTS.md (loadKnownAtoms)."

Full history: this is the real-world layout this tool's own README tells
people to point it at -- `xctidy Tests` names the top-level `Tests/`
directory, but SwiftPM nests each target's specs one level below that
(`Tests/FooKitTests/*.swift`), never directly inside `Tests/` itself. A
non-recursive scan over the directory passed here would find zero atoms
and silently fall back to the bare paren-depth heuristic for every name
-- exactly the bug seen against a real project's `make test | xctidy`
output, where a comma-free-of-parens description like "decodes the name,
size, time, and url" got split into four spurious nested levels. See
`loadKnownAtoms`'s own note above (in `PathSplitting.swift`) for the full
root-cause story.

## Tests/XctidyKitTests/SplitPathSpec.swift

### `SplitPathSpec` (class)
No comment kept in source; same reasoning as `EngineSpec` above --
duplicates `docs/DEVELOPMENT.md`'s "Test" section.

History: one `QuickSpec` class per file, one top-level `describe` per
file, matching the file's subject (here, `splitPath` from
`PathSplitting.swift`).

### `context("when it can't trust the atom dictionary")` -> "falls back to the heuristic when the decomposition is ambiguous"
Kept a one-line comment in place: "Deliberately ambiguous: two valid
decompositions exist for this atom set, so splitPath must fall back to
the heuristic."

## Tests/XctidyKitTests/VersionFlagSpec.swift

### `VersionFlagSpec` (class)
No comment kept in source; same reasoning as `EngineSpec` above --
duplicates `docs/DEVELOPMENT.md`'s "Test" section.

History: one `QuickSpec` class per file, one top-level `describe` per
file, matching the file's subject (here, `wantsVersion` from
`VersionFlag.swift`).
