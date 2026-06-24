# Working with xctidy

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

The engine itself is a Swift port of `tools/test_formatter.py` from the
`next-caltrain-swift` sibling repo (see that repo's `docs/COWORK.md`, "Test
output formatting"), reworked to read xcodebuild's raw output instead of
post-processing xcbeautify's already-flattened text. Reading the raw protocol
directly is what makes failure-folding possible here (see
`docs/HOW_IT_WORKS.md`, "Failure folding") -- the Python version couldn't do
that because by the time text reached it, xcbeautify had already joined a
failing test's name and failure reason with the same `", "` separator the
name itself uses internally.

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
  implement the same dictionary-based comma-disambiguation as the Python
  tool's `load_known_atoms()`/`split_path()`. `Engine` is the stateful
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

`.classic` (default) is the original Python tool's look: glyph (`✔`/`⊘`/`✖`)
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
