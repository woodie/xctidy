# Working with xctidy

Cross-project conventions (git locks, sandbox toolchain) are in `~/workspace/woodie/docs/COWORK.md`.

`xctidy` is a standalone Swift CLI that parses raw `xcodebuild
test`/`swift test` output directly -- the same textual protocol xcpretty and
xcbeautify both regex-match -- into a nested `describe`/`context`/`it` tree,
rendered in any of three named conventions (`--classic`/`--fd`/`--spec`; see
`docs/HOW_IT_WORKS.md`, "Output styles"). It started as a proof-of-concept
built ahead of proposing the same raw-output approach as a built-in mode for
upstream [`cpisciotta/xcbeautify`](https://github.com/cpisciotta/xcbeautify)
-- but it's since grown into its own standalone formatter with its own name
and its own fastlane drop-in-replacement story. (A draft GitHub issue
sketching that upstream pitch used to live as a loose file one level up,
`../xcbeautify-fd-PROPOSAL.md`, outside this repo; its useful content has
been folded into `docs/HOW_IT_WORKS.md`'s "Background" and "Known
limitations" sections, and the original was scrubbed -- see "Where we left
off" below.)

The engine started life as a Python proof-of-concept -- xctidy's own first
version, not a port of some separately maintained tool -- that only existed
for a few hours before being rewritten in Swift. That rewrite is also what
unlocked reading xcodebuild's raw output directly instead of post-processing
xcbeautify's already-flattened text, which is what makes failure-folding
possible here (see `docs/HOW_IT_WORKS.md`, "Failure folding") -- the Python
prototype couldn't do that, since by the time text reached it, xcbeautify
had already joined a failing test's name and failure reason with the same
`", "` separator the name itself uses internally.

## Naming history

The repo/package started life as `xcbeautify-fd` (an `-fd`-suffix nod to
RSpec's `-fd` flag). That undersold it once `--classic`/`--spec` existed
alongside `--fd` -- it read as "just an -fd clone." Renamed to `xcpolish`
first, then -- the user's final call, made by browsing a thesaurus entry for
"tidy" rather than picking from xc-prefixed candidates -- to **`xctidy`**,
which is the name everywhere now: package, executable, library target
(`XctidyKit`), directory names, and all docs.

## Edit cycle

Cowork has no Swift toolchain in its sandbox, so `swift build`/`swift test`
can't be run or verified here. Cowork edits `Sources/`/`Tests/` directly with
its file tools, reasons about expected behavior, and hands back exact
verification commands for the user to run on their own Mac. Treat any change
as unverified until the user confirms a real build/test run.

The sandbox also can't unlink (`rm`/`rmdir`) files inside the mounted
workspace folder (a virtiofs restriction) -- but a same-filesystem `mv`
*does* work, including renaming a directory in place (confirmed by the
`Sources/XcbeautifyFDKit` → `Sources/XcpolishKit` → `Sources/XctidyKit`-style
renames done across this arc). When a file needs deleting rather than
renaming, Cowork blanks its *content* to a short comment explaining why and
pointing at the exact `git rm`/`rm`/`rmdir` command for the user to run
themselves. `Tests/XctidyKitTests/EngineTests.swift` and
`Sources/xctidy/main_copy2.swift` are in exactly that state right now (see
"Where we left off" below for the full cleanup list).

Most of this arc -- the Quick/Nimble conversion, the render-style split, the
rename -- is now committed (`b41656d`, after the user confirmed a real
build/test run; see "Where we left off" below). Docs-in-progress edits
within a single Cowork turn typically still sit uncommitted at any given
moment -- check `git status` rather than assuming either way.

## Architecture

- `Sources/XctidyKit/Engine.swift` -- the core engine. `Matchers` mirrors
  xcpretty's `parser.rb` regexes (one deliberate improvement: the
  suite/class capture uses `\S+` instead of xcpretty's ambiguous `(.*) (.*)`,
  since class names never contain spaces). `loadKnownAtoms`/`splitPath`
  carry over the same dictionary-based comma-disambiguation algorithm and
  function names from xctidy's brief original Python prototype's
  `load_known_atoms()`/`split_path()`. `Engine` is the stateful
  line-by-line renderer; `RenderStyle` controls which of the three output
  styles it produces.
- `Sources/xctidy/main.swift` -- CLI entry point. Reads stdin line by line,
  feeds `Engine`, prints `engine.finish()`. Flags: `--classic` (default),
  `--fd`, `--spec`, `--style <name>`/`--format <name>` (`fd` doubles as
  `documentation`), or, for the two non-default styles, the concatenated
  short forms `-fd`/`-fs` (the `-f<letter>` idiom RSpec itself uses --
  `rspec -fd` is `-f` immediately followed by a single-letter formatter
  code, not its own dedicated flag). No `-fc`: classic is already what no
  flag gets you, so a short form for it would just reproduce default
  behavior and confuse people about its purpose. Positional arg is the
  specs directory passed to `loadKnownAtoms`.
- `docs/HOW_IT_WORKS.md` -- the comma problem, failure folding, build-noise
  suppression, a full description of the three output styles, and where
  `xctidy` fits in a fastlane pipeline (`xcodebuild_formatter`). Read that
  before touching `RenderStyle` or `renderCase`/`finish()` in `Engine.swift`.
- `docs/DEVELOPMENT.md` -- the contributor-facing build/test/project-layout
  guide, separate from this file. This file (`COWORK.md`) is Cowork's own
  session notes; `DEVELOPMENT.md` is the durable doc a human contributor
  (not Cowork) would actually read.

### Render styles

`.classic` (default) is the look xctidy's original Python prototype had: glyph (`✔`/`⊘`/`✖`)
plus the per-test `(N seconds)` xcodebuild reports. `.fd` clones real
RSpec's `-fd` formatter's *leaf* rendering only: no glyph, yellow
`(PENDING)` instead of `(SKIPPED)`. `.spec` clones Mocha/Jest's
`✔`-green/gray-name leaf convention, also leaf-only. All three styles end
with the exact same closing footer, byte-for-byte: real xcbeautify's own
`Test Succeeded`/`Test Failed` + `Tests Passed: X failed, Y skipped, Z
total (N seconds)`. `.fd`/`.spec` do *not* additionally print RSpec's
`Finished in.../X examples` or Mocha's `N passing (Ttime)` -- an earlier
pass stacked that native summary before the xcbeautify footer, but real
side-by-side output made the three styles' endings look inconsistent
("the differences in the footer are confusing" -- direct user feedback),
so the native summaries were dropped in favor of one shared, unambiguous
ending. Full detail in `docs/HOW_IT_WORKS.md`'s "Output styles" section --
don't duplicate it here, that doc is the source of truth.

## Tests

Quick/Nimble (added as test-only dependencies in `Package.swift`) so the
suite can dogfood the tool's own headline feature -- a real, genuinely
comma-flattened Quick test name to disambiguate, not just a hand-built
fixture string.

- `Tests/XctidyKitTests/EngineSpec.swift` -- the main spec, a single
  `final class EngineSpec: QuickSpec` with `override class func spec()`
  (Quick 7.x uses a *class* method here, not an instance method --
  `override func spec()` fails to compile with "method does not override any
  method from its superclass"). Nested `describe`/`context`/`it` covering
  `loadKnownAtoms`, `splitPath` (both the dictionary-disambiguation path and
  the heuristic fallback), and `Engine` (tree rendering, noise suppression,
  color output, and all three render styles' leaf/footer behavior).
- `Tests/XctidyKitTests/AnsiColorDemoSpec.swift` -- a small, *real* Quick
  spec (not just fixtures) proving the comma-disambiguation logic against
  genuine Quick-generated output, including a deliberately tricky
  bare-prose-comma case (no parens at all) that only the atom-dictionary
  approach resolves correctly -- the paren-depth heuristic alone would
  over-split it.
- `Tests/XctidyKitTests/EngineTests.swift` -- superseded. Used to be a flat
  `XCTestCase` with the same cases now in `EngineSpec.swift`; blanked to a
  placeholder comment (sandbox can't delete it -- see "Edit cycle" above).
  **Still needs `git rm Tests/XctidyKitTests/EngineTests.swift` from the
  user.**

## Where we left off (2026-06-23)

Most recent work, in order: (1) split the old two-way `--fd`/`--spec` flag
into the three-way `--classic`/`--fd`/`--spec` style now documented above,
making `--classic` the default and byte-for-byte what the original Python
tool produced; (2) reworked `--classic` to match a `swift.txt` reference
sample exactly (glyph + per-leaf elapsed time, which an earlier pass had
dropped); (3) added a Mocha-style `N passing (Ttime s)` summary footer to
`--spec`, matching a `kotlin.txt` reference sample; (4) renamed the project
twice -- `xcbeautify-fd` → `xcpolish` (interim) → **`xctidy`** (the user's
final answer, picked by browsing a thesaurus entry for "tidy" rather than
from the xc-prefixed shortlist) -- across `Package.swift`, `Sources/`,
`Tests/`, and all source comments, plus the local project folder
(`~/workspace/xcbeautify-fd` → `~/workspace/xctidy`); (5) rewrote
`README.md`, `docs/HOW_IT_WORKS.md`, and this file to reflect the new name,
the three styles' real current behavior, and `xctidy`'s positioning as a
fastlane drop-in *replacement* formatter (same `xcodebuild_formatter`
pipeline slot as xcbeautify/xcpretty, not a post-processor chained after
either) -- including a concrete `Fastfile` `scan(xcodebuild_formatter:
...)` snippet, verified against fastlane's own docs; (6) confirmed on the
user's actual Mac -- `swift build -c release` succeeds and all three styles'
real output matches what's documented (glyph+timing for `--classic`, the
RSpec footer for `--fd`, the Mocha footer for `--spec`); (7) scrubbed
`../xcbeautify-fd-PROPOSAL.md` (the draft upstream-xcbeautify GitHub issue
mentioned above) after folding its useful technical content -- the
ginkgo-fd/onsi-ginkgo#1670 provenance and the parallel-testing/Quick-Nimble-
scope caveats -- into `docs/HOW_IT_WORKS.md`'s "Background" and new "Known
limitations" sections; (8) rewrote `README.md` to mirror
[`cpisciotta/xcbeautify`'s README](https://github.com/cpisciotta/xcbeautify/blob/main/README.md)
structure (badge row, screenshot, checkbox feature list, Installation/Usage/
Development/Contributing sections) and added a "Why xctidy instead of
xcbeautify or xcpretty?" section giving an honest, scoped answer -- xctidy
only solves the Quick/Nimble comma-disambiguation + failure-folding problem,
it has no build-phase formatting, no Linux support, no JUnit, no CI-UI
renderers, so xcbeautify/xcpretty are still the right tool outside that one
case; (9) generated `.readme-images/example.png`, a synthetic terminal
screenshot of `--classic` output (light theme, traffic-light window chrome,
built with Pillow since the sandbox has no headless browser) to stand in
for the real screenshot the user may swap in later; (10) added
`docs/DEVELOPMENT.md` as the contributor-facing counterpart to this file
(build/test/project-layout/releasing, kept separate from these Cowork
session notes).

Status as of this doc:

- `Engine.swift`, `main.swift`, `EngineSpec.swift`, and `AnsiColorDemoSpec.swift`
  are all consistent with each other under the `xctidy` name and the 3-way
  style split, and **confirmed working** via a real `swift build`/`swift
  test` run on the user's Mac (not just reasoned-about from the sandbox).
- `README.md`, `docs/HOW_IT_WORKS.md`, and `docs/DEVELOPMENT.md` describe all
  three styles accurately and document the fastlane integration.
- The GitHub repo rename is **done** -- `git remote -v` now shows
  `git@github.com:woodie/xctidy.git`, so that's no longer outstanding.
- Badges: README currently has only Swift-version and License badges (both
  true today, no infra needed). The user explicitly deferred CI/release
  badges -- "When we get workers set up, we can add badges" -- so there's no
  `.github/workflows/` CI yet and none should be added until asked. A
  commented-out placeholder in `README.md` marks where those two badges go
  once that exists.
- **Not yet done**: nothing else build/test-related. Remaining work is file
  cleanup (below) and committing this session's docs work.
- Cleanup the user still needs to run themselves (sandbox can't delete
  files -- see "Edit cycle" above):

  ```
  git rm Tests/XctidyKitTests/EngineTests.swift
  git rm Sources/xctidy/main_copy2.swift
  rm Sources/xctidy/_scratch_test.txt
  rmdir Sources/TestDirRename2
  rm ~/workspace/xcbeautify-fd-PROPOSAL.md
  ```

- `git status` at the time of writing: the Quick/Nimble conversion, the
  render-style split, and both renames are already committed as `b41656d`
  ("Rename xcbeautify-fd to xctidy; add --classic/--fd/--spec styles") --
  repo history is `d8c27e5` (initial scaffold) → `ecf5d6d` (first Swift
  Package implementation) → `b41656d`. Only this docs pass (this file,
  `docs/HOW_IT_WORKS.md`, the new `README.md`/`docs/DEVELOPMENT.md`/
  `.readme-images/example.png`) is uncommitted and unpushed right now.

## Later session: footer iteration, flag redesign, footer un-stacking

After the above was committed, several more rounds happened against the
real built binary on the user's Mac: (1) added the xcbeautify-style
`Test Succeeded`/`Tests Passed` footer to `--classic`; (2) extended it to
`--fd`/`--spec` too, stacked *after* each style's own native summary
(RSpec's `Finished in.../X examples`, Mocha's `N passing (Ttime)`);
(3) added `--format <name>`/`-fd`/`-fs` as aliases alongside the existing
`--classic`/`--fd`/`--spec`/`--style <name>` flags, then dropped a `-fc`
short form that was floated for symmetry -- the user pointed out it "does
nothing" since classic is already the default, so a short form for it
would only confuse people; (4) after seeing real terminal output for all
three styles side by side, the user said "the differences in the footer are
confusing" -- the stacked native summaries made `--classic`/`--fd`/`--spec`
end with a different shape (0, 2, or 1-3 extra lines) before reaching the
identical closing two lines. Resolved by **removing** the native
RSpec/Mocha summaries entirely rather than keeping them: `--fd`/`--spec`
still render their leaves in RSpec's/Mocha's own style, but the closing
footer is now byte-for-byte identical across all three styles, no
exceptions. `Engine.swift` (`finish()`, the `RenderStyle` doc comment),
`EngineSpec.swift`, `main.swift`'s usage comment, `README.md`,
`docs/HOW_IT_WORKS.md`, and the "Render styles" section above were all
updated to match. The user then confirmed this on their own Mac --
pasted three real `swift test | xctidy` screenshots dogfooding
`EngineSpec.swift`'s own suite (33 examples, 0 failures) across all three
styles, all ending in byte-for-byte the same footer -- so this is no
longer unverified.

The user then built `docs/example.gif` themselves (a real terminal capture,
not a Cowork-synthesized one) cycling through all three styles, and asked
Cowork to check/fix it: original frame order was `fd -> spec -> classic` at
2000ms/frame; Cowork reordered it to the requested `--classic -> --spec ->
--fd` (`na -> fs -> fd`) at 3000ms/frame and saved it back to the same path.
Cowork also built its own synthetic comparison GIF
(`.readme-images/footer-consistency.gif`, generated by
`make_footer_gif.py` -- not checked into the repo's working tree from this
session, just produced ad hoc for comparison) reconstructed from the literal
`it(...)` strings in `EngineSpec.swift`, labeled per-frame with the style
name/flag; useful for spotting that the user's real terminal doesn't
visibly render `--spec`'s gray-dimmed passing names (ANSI SGR `2`/faint is
inconsistently supported across terminal emulators -- likely just a
terminal-rendering quirk, not an xctidy bug). The user picked their own real
GIF over Cowork's synthetic one. `README.md`'s screenshot was swapped from
the static `.readme-images/example.png` to `docs/example.gif`, and the
"screenshot above is `--classic`" sentence in the "Output styles" section
was rewritten to describe the cycling GIF instead.

**Final outcome, after the user actually committed and pushed (`0b3d201`,
"Cloean up test footer and update README."):** the animated GIF turned out
to be problematic (not specified exactly how -- e.g. GitHub README preview,
file size, or just not looking right -- the user only said "the animated
gif was problematic"), so the user replaced it with a new static screenshot,
`docs/example.png`, of the `--fd` style specifically, and pointed README's
top image at that instead. `docs/example.gif` is still committed in the
repo (`0b3d201` added both files) but is now unreferenced from `README.md`.
Cowork caught that the "Output styles" caption paragraph still described
"the GIF above cycles through all three" -- now stale/wrong against the
static `--fd` PNG actually in place -- and rewrote it to say "The screenshot
above is `--fd`" instead. If the unreferenced `docs/example.gif` should be
removed from the repo entirely, that's a `git rm docs/example.gif` for the
user to run (see "Edit cycle" above -- sandbox can't delete files in the
mounted workspace).

The user then asked to switch the README's "Build from source" install
path to `make install`, matching real xcbeautify's exact 3-line pattern
(`git clone` / `cd` / `make install`) rather than the manual `swift build -c
release && cp .build/release/xctidy /usr/local/bin/` it had. xcbeautify's
own `Makefile` was fetched from GitHub as a reference, but only a small
subset of it actually applies here -- xcbeautify's has Linux/Docker cross-
compile packaging, a `release`/version-bump target (sed-editing a
`Version.swift` xctidy doesn't have), `tools/format`/`tools/lint`/`tools/
measure` scripts that don't exist in this repo, and a `brew bundle` `deps`
target with no `Brewfile` here -- none of that was copied in, since xctidy
has no CI, no Linux support, and no such tooling yet (copying it in would
just be dead make targets). Added a new top-level `Makefile` with the parts
that do apply: `build`/`test`/`install`/`uninstall`/`clean`/`xcode`,
`PREFIX`-overridable (defaults to `/usr/local`, same as xcbeautify's).
Verified with `make -n install`/`make -n build`/`make -n uninstall` (dry-run,
since the sandbox has no `swift` on `PATH` to do a real build) -- recipe
lines use real tabs (confirmed via `cat -A`), and the printed commands match
intent; `BUILD_DIRECTORY` resolved to empty in the dry run only because
`swift build --show-bin-path` couldn't run here, which will resolve
correctly on the user's Mac. `README.md`'s "Build from source" section
updated to the 3-line pattern; `docs/DEVELOPMENT.md`'s "Build" section
(which still documents raw `swift build`/`swift build -c release` for
day-to-day contributor iteration) got a short added note pointing at the
Makefile as the end-user install path instead.

The user then gave editorial feedback on the README itself: (1) general
praise for xcbeautify's README structure, with the caveat that its
"GitHub Actions"/"TeamCity"/"Azure DevOps Pipeline" `Usage` subsections
should live elsewhere rather than in the main flow -- noted as taste/
context, but no action taken in this repo since `xctidy` has no analogous
CI-renderer sections to relocate (see "Known limitations": no CI-UI
renderers). Worth remembering if `xctidy` ever grows renderer-specific
integration docs. (2) Replaced the two-paragraph intro ("xctidy turns flat,
comma-joined... It reads xcodebuild's raw output directly... not a
post-processor...") with a single bolded sentence: "xctidy brings RSpec's
documentation format and Mocha's spec output format to `xcodebuild`." The
dropped "formatter, not a post-processor" framing isn't lost -- it's still
covered in the "Why xctidy instead of xcbeautify or xcpretty?" section
right below ("Both read the same raw xcodebuild protocol, so they slot into
the same pipeline position..."). (3) Replaced the checkbox-style `Features`
list (which mixed shipped features with two `[ ]` not-yet items linking to
`docs/HOW_IT_WORKS.md#known-limitations`) with a plain 4-bullet list per
the user's exact wording: concise/readable output, familiar RSpec/Mocha
conventions, the fastlane drop-in, Swift static binary. This drops the
README's only link to the Known limitations section -- the limitations
themselves are still fully documented in `docs/HOW_IT_WORKS.md` and
`docs/DEVELOPMENT.md`, just no longer surfaced from the README itself. Flag
this if discoverability of that section from the README matters later.

The user then did a further round of README cleanup entirely on their own
(four commits -- `51e6de2`, `0162e6d`, `5cd70a9`, `84e5dab` -- on top of
Cowork's edits above), discovered after the fact via `git log`/`git diff`.
Notable changes: the intro reverted from Cowork's "xctidy brings RSpec's
documentation format and Mocha's spec output format to `xcodebuild`" sentence
back to the user's own earlier first draft, "`xctidy` adds nested
describe/context/it tree support to `xcodebuild`. An alternative to
xcbeautify and xcpretty written in Swift." -- presumably a deliberate final
choice rather than an accidental revert, since it's the user's own wording
either way. The entire "Why xctidy instead of xcbeautify or xcpretty?"
section was deleted (its "Reach for xctidy when:"/"Keep xcbeautify/xcpretty
when:" guidance and the Quick/Nimble-only scoping note are gone from
`README.md`, though the same scoping detail still lives in
`docs/DEVELOPMENT.md`'s "Known limitations to be aware of"). The Output
styles table lost its "Short form" column and got two Convention-column
rewords. The Features list's last bullet picked up "and" ("Written in Swift
and compiles to a static binary"). None of this broke any links --
`docs/HOW_IT_WORKS.md#output-styles` and `docs/DEVELOPMENT.md` are both
still referenced and still resolve.

Immediately after, the user asked Cowork to go further on the "Output
styles" section specifically: "rip out all the explanation about flags and
just get to the basics, a couple sentences." Cowork cut the paragraph
explaining `--format <name>`/`--style <name>` and the `-f<letter>` RSpec
short-form idiom (entirely flag-mechanics explanation, now undocumented in
README -- still discoverable via `main.swift`'s usage comment or
`docs/HOW_IT_WORKS.md` if needed), and trimmed the byte-for-byte-footer
paragraph down to one sentence. The section is now: one intro sentence, the
table, one closing sentence pointing at `--fd`'s screenshot and the
`docs/HOW_IT_WORKS.md` full-sample link.

Two open questions from earlier rounds remain unanswered: whether to
`git rm docs/example.gif` (still committed, still unreferenced from
`README.md` since the `--fd` PNG swap), and whether the Known-limitations
link should be restored to the README now that two separate edits have
removed it from the main flow.

The user then made a further README edit themselves (uncommitted at time
of writing) swapping every remaining `--fd` for the short form `-fd`
(fastlane example, Output styles table, the `--fd` screenshot caption) and
rewording the table's Convention column ("RSpec's doc format"/"Mocha's spec
format"). That, plus an explicit instruction -- "I just want to have `-fd`,
`-fs` and `--format documentation|spec` so let's get rid of everything else
in `docs/HOW_IT_WORKS.md`" -- made clear this isn't just a docs-wording
pass, it's a real flag-surface decision: drop `--classic`/`--fd`/`--spec`
(the long boolean flags) and `--style` (the `--format` alias) entirely.
Since the project's own convention treats the docs as a description of
actual behavior, not aspirational copy, Cowork changed the code to match
rather than leaving docs and `main.swift` out of sync: `Sources/xctidy/
main.swift`'s flag-parsing switch now only recognizes `-fd`, `-fs`, and
`--format documentation`/`--format spec` (the `--classic`/`--fd`/`--spec`
cases, the `--style` alias, and `--format classic`/`--format fd` were all
removed), and its usage comment was rewritten to match. `Engine.swift`'s
two comments mentioning `--fd`/`--spec`/`--style`/`--format` (around the
classic-skip-glyph rationale and the shared-footer note) were updated to
the new flag names -- the `RenderStyle` enum's case names (`.classic`/
`.fd`/`.spec`) are untouched, this is CLI surface only, not a rename of the
internal styles. `docs/HOW_IT_WORKS.md`'s "Output styles" intro paragraph
was rewritten to name only the new surface (dropping the `-f<letter>`-idiom
digression and the now-pointless "no `-fc`" aside), its three per-style
paragraphs and the fastlane-pipeline section had their `--fd`/`--classic`/
`--spec` mentions swapped to `-fd`/`-fs`/"default (no flag)", and the
ASCII-art sample blocks were left untouched (they're leaf-rendering output,
not flag syntax). `docs/DEVELOPMENT.md`'s one mention of the three styles
was updated the same way. Verified with a repo-wide grep for `--classic`/
`--fd`/`--spec`/`--style` after the edits -- zero hits left outside this
file's own historical narrative; `swift build`/`swift test` weren't run
(no `swift` on this sandbox's `PATH`, same limitation as the Makefile
round) so the user should run `swift test` on their Mac to confirm
`EngineSpec.swift` still passes -- nothing in the test suite invokes CLI
flags directly (it tests `Engine`/`RenderStyle` directly), so this should
be a no-op for tests, but worth a real run regardless.

The user committed the working-tree state from that round across two of
their own commits (`fca55e3` "Clean up format flags.", `81eaee8` "Tidy up
the flag section."), then said: "The original `test_formatter.py` was
created the day before we created this project, and we will replace it
today, so no need to reference it." -- they'd already made one docs edit
themselves (`1528949`, "Remove reference to original test_formatter.py.",
touching only `docs/HOW_IT_WORKS.md`'s "default (no flag)" paragraph) but
that edit left a dangling sentence fragment ("the cross-reference into the
`Failures:` section --  the name uses internally") and dropped the
per-test-timing/coloring detail entirely. Cowork fixed that paragraph (restored
the "(N seconds)"/coloring description, repaired the grammar, kept the
test_formatter.py mention out) and then swept the rest of the codebase for
the same lineage framing, since the instruction was "no need to reference
it" project-wide, not just in that one paragraph: deleted
`docs/HOW_IT_WORKS.md`'s "Background" section's opening paragraph entirely
(the "this engine started as a Python post-processor... `xctidy` is a
from-scratch Swift implementation" framing -- redundant with "Failure
folding" above it anyway, which already explains why reading raw
`xcodebuild` output matters without naming the old script), and rewrote
four code comments in `Sources/XctidyKit/Engine.swift` (the comma-
disambiguation header, the `RenderStyle` doc comment, the `timedSuffix`
comment, and the skip-glyph rationale comment) plus one in
`Sources/xctidy/main.swift`'s usage block, all of which cited
`tools/test_formatter.py` as the thing being matched/ported-from. Left
alone: `docs/COWORK.md`'s own earlier entries (this file is a historical
log of what was true at the time, not living docs) and
`EngineSpec.swift`'s `next-caltrain-swift` path references (those cite
where the real fixture strings/paths came from, not test_formatter.py's
lineage -- a different kind of reference). Verified with a repo-wide grep
for `test_formatter` afterward -- the only remaining hit is this file's own
earlier narrative entry, as intended.

## Later session: install permissions, a stdin gotcha, and a sudo fix

Three short rounds, all triggered by the user actually running the
installed binary on their Mac rather than just building it. First: `make
install` failed with `cp: /usr/local/bin/xctidy: Permission denied` --
expected on Apple Silicon, where `/usr/local/bin` is root-owned out of the
box (Intel Macs/Homebrew users often have it `chown`'d to themselves, which
is why this isn't universal). Cowork explained the cause and offered two
options without picking one: `sudo make install`, or `make install
PREFIX=$HOME/.local` (no sudo, but `$HOME/.local/bin` then needs to be on
`PATH`).

Second: the user reported "the binary does not work" after installing with
`sudo` (confirmed via `ls -la` showing a root-owned, correctly-permissioned
executable). Rather than guess, Cowork asked for the exact command/output,
suspecting the stdin-block gotcha -- `xctidy` reads from stdin and a bare
invocation with nothing piped in just hangs, it's not actually broken. The
user confirmed: `swift test 2>&1 | xctidy Tests` produced a correct,
fully-rendered 33-example tree (hand-verified the leaf count against the
footer's "33 total"), so the binary was fine all along.

Third: the user then pasted a second run, `swift test | xctidy Tests`
(no `2>&1`), prefaced "this is fine too...", showing three extra lines above
the tree -- `Building for debugging...`, `[7/7] Write swift-version-...txt`,
`Build complete! (0.33s)`. Cowork initially mischaracterized this,
attributing the first run's clean output to the `2>&1` redirect itself. The
user corrected that framing directly: "Adding `2>&1` simply hides what
something good is happening" -- i.e. crediting `2>&1` as a fix was wrong;
the real explanation needed tracing, not a guess. Reading `Engine.swift`'s
`feedLine` confirmed its noise suppression is default-deny (anything not
matching a known `xcodebuild`-test-protocol line, and not an `error:`/
build-failed marker, is silently dropped with no `emit()` call) -- which
means those three SPM lines were never reaching `feedLine` at all in the
no-`2>&1` run. `swift build`/`swift test` write their own build-progress
lines to **stderr**, not stdout; without `2>&1`, stderr bypasses the pipe
entirely and prints straight to the terminal, interleaved with `xctidy`'s
stdout but completely unprocessed by it. With `2>&1`, those same lines do
get fed into `feedLine`, where the existing default-deny fallthrough
already drops them correctly -- which is what made the first run look
clean. Net result: no `Matchers`/noise-filter code change was needed or
made; the suppression logic was already correct on both paths, and the fix
was purely in how Cowork explained the mechanism, not in `Engine.swift`. A
concrete falsifiable check was offered to confirm the stderr theory:
`swift test 2>/dev/null | xctidy Tests` should make those three lines
disappear outright (discarded with stderr) rather than reappear filtered.

The user then asked to make `make install` actually prompt for a sudo
password instead of failing outright -- turning the first round's two
manually-chosen options into one command that does the right thing
automatically. `Makefile` gained a `SUDO` variable, computed once via
`$(shell ...)`: starting from `$(PREFIX)/bin`, walk up to the nearest
*existing* ancestor directory and test its writability, falling back to
`sudo` only if that ancestor isn't writable. The ancestor-walk (rather than
testing `$(PREFIX)/bin` directly) matters for a not-yet-created `PREFIX`
like `$HOME/.local` -- `$HOME/.local/bin` doesn't exist yet on a fresh
machine, so testing it directly would wrongly fall back to `sudo`; walking
up to `$HOME`, which does exist and is writable, gives the right answer.
`install`'s `mkdir`/`cp` and `uninstall`'s `rm` are now all prefixed with
`$(SUDO)`. Verified with `make -n install`/`make -n uninstall` dry runs
under both a locked-down default `PREFIX` (emits `sudo mkdir`/`sudo cp`)
and a writable override `PREFIX=/tmp/...` (emits plain `mkdir`/`cp`, no
prompt) -- both matched the intended behavior exactly. `docs/DEVELOPMENT.md`
was updated to describe the new conditional-sudo behavior alongside its
existing `PREFIX` explanation. Not yet done: `git rm docs/example.gif` and
restoring the Known-limitations README link both remain open from earlier
rounds, still unanswered by the user.

## Later session: the comma-disambiguation gap was a non-recursive glob

The user converted a separate sibling project's (`~/workspace/zouk`) XCTest
suite to Quick/Nimble (that conversion is documented in `zouk`'s own
`docs/COWORK.md`, not here), then piped its real `make test` output through
`xctidy` and got back a mis-rendered tree: bare-prose-comma descriptions
with no parentheses at all -- `"decodes the name, size, time, and url"`,
`"is nil, along with downloadedAt"`, `"...baseURL, replacing the whole
path"` -- each got split into spurious extra nesting levels at every
comma, even though `loadKnownAtoms`/`splitPath`'s dictionary-based
disambiguation (see "Architecture" above) is specifically supposed to
handle exactly this case, and `AnsiColorDemoSpec.swift` already has a
passing test proving the algorithm handles a bare-prose-comma fixture
correctly. So the algorithm itself wasn't broken -- something was
preventing it from ever engaging for this real invocation.

Root cause, confirmed by reading `loadKnownAtoms` in
`Sources/XctidyKit/PathSplitting.swift`: it scanned `*.swift` files
*directly inside* the given `specsDir` via `contentsOfDirectory(atPath:)`
-- non-recursive, carried over directly from xctidy's brief original Python
prototype's `Path(specs_dir).glob("*.swift")`. That's incompatible with this tool's
own documented usage. The README's canonical examples (`xcodebuild test
[flags] | xctidy Tests`, `swift test 2>&1 | xctidy Tests`) and
`docs/HOW_IT_WORKS.md`'s "Where this fits in a fastlane pipeline" section
all tell people to pass the top-level `Tests` directory -- but SwiftPM
puts each target's specs one level below that, in
`Tests/<ModuleName>Tests/*.swift` (`Tests/ZoukKitTests/*.swift` for zouk,
`Tests/XctidyKitTests/*.swift` for this very repo), never directly inside
`Tests/` itself. A non-recursive glob over `Tests/` finds zero `.swift`
files there, so `atoms` came back empty for the exact invocation the
README recommends -- which silently drops `splitPath` to the paren-depth
heuristic for every single name, the same fallback path that already had
a passing test (`SplitPathSpec.swift`'s "falls back to the heuristic when
atoms is empty") confirming *that* path mis-splits bare prose commas. The
gap was real and exactly matches the zouk symptom: every prior test
covering `loadKnownAtoms` (`LoadKnownAtomsSpec.swift`) and the
dictionary-disambiguation path (`SplitPathSpec.swift`,
`AnsiColorDemoSpec.swift`) wrote its fixtures *directly inside* a flat
temp directory -- none of them exercised the realistic nested
per-target-subdirectory layout the README itself prescribes, so the bug
had no test surface to be caught on.

Fix: `loadKnownAtoms` now calls `subpathsOfDirectory(atPath:)` instead of
`contentsOfDirectory(atPath:)`, walking the whole tree under `specsDir`
rather than just its immediate children, so `xctidy Tests` actually finds
every spec file regardless of how many target subdirectories sit
underneath it. Added a regression case to `LoadKnownAtomsSpec.swift`
("recurses into per-target subdirectories like Tests/<ModuleName>Tests/")
that writes a fixture spec one level down in a `FooKitTests/` subdirectory
and asserts `loadKnownAtoms` still finds its atoms -- this is the case
that would have caught the bug before it ever reached a real project.
Updated `loadKnownAtoms`'s doc comment to explain the old non-recursive
behavior, why it was wrong, and why the new recursive scan is correct
instead of just describing current behavior in isolation. No changes were
needed in `splitPath`, `Engine.swift`, or any CLI flag -- the
disambiguation algorithm itself was always correct, it just never received
the atoms it needed.

Made by inspection only per the sandbox's no-Swift-toolchain limitation
above -- the existing `LoadKnownAtomsSpec.swift`/`SplitPathSpec.swift`
cases were traced by hand against the new `subpathsOfDirectory` call to
confirm none of them regress (none use nested subdirectories, so their
expected output is unchanged), but this needs a real `swift test` run on
the user's Mac to confirm, and then a real
`make test | xctidy Tests` (or `swift test 2>&1 | xctidy Tests`, run from
`~/workspace/zouk` with the path adjusted to that repo's `Tests` directory)
against `zouk` to confirm the original bare-prose-comma symptom is gone.

## Later session: `-fv`, ported from `gorderly`

`gorderly` (the Go equivalent of this tool, `~/workspace/gorderly`) added
a `-fv`/`--format vitest` style matching [Vitest](https://vitest.dev)'s
own terminal conventions -- built after checking Vitest's actual reporter
source (`packages/vitest/src/node/reporters/renderers/{utils,figures}.ts`)
rather than guessing from its docs: `✓`/`×`/`↓` glyphs (the fail glyph is
a multiplication sign, not `✗`), a two-toned green duration (plain green
number, a separate lighter `brightGreen`/92 for the `ms`/`s` unit), and a
footer with labels right-justified to 11 columns. The user asked for the
same style here.

Added `RenderStyle.vitest` to `Engine.swift`, matching `gorderly`'s glyph
choices and duration formatting exactly (`vitestDurationParts` mirrors
`gorderly`'s `formatVitestDurationParts`: whole ms under 1000ms, seconds
to two decimals at or above), plus `-fv`/`--format vitest` in
`main.swift`. One real gap, left deliberately unfilled: Vitest's `Test
Files` line isn't emitted. `gorderly`'s equivalent counts cleanly because
one `PackageResult` per Go package was already unambiguous; XCTest's own
`Test Suite` output nests a per-class suite inside "All tests"/"Selected
tests" aggregate wrapper suites, and that nesting isn't verified against
real `xcodebuild` output here (no Swift/Xcode toolchain in this sandbox,
and no sample output for it in this repo's own test fixtures) -- counting
every `Test Suite ... passed/failed` line would likely over-count the
wrapper suites as if they were their own files. `emitVitestFooter` in
`Engine.swift` has a comment marking this as a follow-up for whoever
checks it against a real `xcodebuild` run.

New coverage in `EngineSpec.swift` (`context("vitest style (-fv)")`):
glyphs for pass/fail/skip, the ms-to-seconds threshold, TTY two-tone
coloring, the footer shape, and an explicit test confirming the `Test
Files` line's absence (so the omission reads as a documented decision,
not an oversight). Also caught and fixed one real bug along the way: the
new comments were initially written wrapped across multiple `//` lines,
matching `gorderly`'s house style -- but this repo's own convention is
one long single-line comment (using `--` as an internal separator, no
wrapping), confirmed by every pre-existing comment in `Engine.swift`.
Collapsed all of the new ones to match.

Made by inspection only, same sandbox limitation as every round above --
confirmed on the user's own Mac afterward: `make test` (all 46 specs
pass, including the new `-fv` block) and `make install` both succeeded.
