## Highlights

- Add `-fv`/`--format vitest`: renders [Vitest](https://vitest.dev)'s own
  terminal conventions -- `✓`/`×`/`↓` glyphs, a two-toned green duration
  (plain green number, lighter unit), and a `Tests`/`Duration` footer with
  labels right-justified to 11 columns. Ported from `gorderly` (the Go
  equivalent of this tool), which verified the glyphs and formatting
  against Vitest's actual reporter source rather than its docs.
- Known gap: no `Test Files` line. XCTest's own `Test Suite` nesting
  ("All tests"/"Selected tests" wrapper suites around each per-class
  suite) isn't verified against real `xcodebuild` output yet, so a
  suite-level count risks over-counting wrapper suites as their own
  files. Left for a future release once checked against a real run.
