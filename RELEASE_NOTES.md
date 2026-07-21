## Fix

- `vitestDurationParts`'s local `ms` variable (added in v0.3.0's `-fv`
  code) violated `identifier_name`'s minimum length under `--strict`.
  `.swiftlint.yml` only excludes single-letter names for pre-reviewed
  cases (loop counters, regex-match locals) -- `ms` wasn't one of them, and
  two characters is short even by that list's standard. Renamed to
  `milliseconds` rather than adding another exclusion; no behavior change.
