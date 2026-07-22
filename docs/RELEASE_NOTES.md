## Fix

`xctidy` always exited 0 regardless of whether any rendered test case
failed -- the only non-zero exits were flag-parsing errors. That meant a
plain `xcodebuild test | xctidy Tests` (without `set -o pipefail`)
reported success even when real tests failed, since the pipeline's exit
status defaulted to the last command's. `xctidy` now exits 1 if
`engine.failures` isn't empty, mirroring gorderly's `main.go`.

`set -o pipefail` is still worth keeping in CI: this only covers failures
xctidy actually rendered, not an upstream build failure that happens
before any test case runs.

## Also

`make test` now builds a debug `xctidy` binary and pipes `swift test`
through it, so the suite dogfoods xctidy's own rendering on every local
run -- matching how `gorderly`'s `test` target self-hosts on the Go side.
