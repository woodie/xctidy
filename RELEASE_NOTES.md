## Fix

- Two lines in `Engine.swift`'s `-fv` code (added in v0.3.0) exceeded
  SwiftLint's 120-character warning threshold -- harmless under normal
  `swiftlint lint`, but CI's `make lint` runs `--strict`, which escalates
  warnings to build-failing errors. Wrapped both onto multiple lines
  (`labelForPassed`'s `.vitest` case, `emitVitestFooter`'s summary-line
  call) with no behavior change. `Tests/.swiftlint.yml` already disables
  `line_length` for spec fixtures, so this only affected real source under
  `Sources/`.
