import Foundation
import XctidyKit

#if canImport(Glibc)
    import Glibc
#else
    import Darwin
#endif

// Usage: xcodebuild test ... | xctidy [-fd|-fs|-fv|--format documentation|--format spec|--format vitest] [path-to-Tests-dir] -- see docs/HOW_IT_WORKS.md's "Output styles" and docs/COMMENTS.md for the full flag reference.

var style: RenderStyle = .classic
var specsDir = "."
var sawPositional = false

func parseStyle(_ raw: String) -> RenderStyle? {
    switch raw {
    case "documentation": return .doc
    case "spec": return .spec
    case "vitest": return .vitest
    default: return nil
    }
}

var args = Array(CommandLine.arguments.dropFirst())

// Checked before the stdin-reading loop, not as a switch case; see wantsVersion's doc comment for why.
if wantsVersion(args) {
    print(xctidyVersion)
    exit(0)
}

var i = 0
while i < args.count {
    switch args[i] {
    case "-fd":
        style = .doc
    case "-fs":
        style = .spec
    case "-fv":
        style = .vitest
    case "--format":
        guard i + 1 < args.count, let parsed = parseStyle(args[i + 1]) else {
            let got = i + 1 < args.count ? args[i + 1] : "<missing>"
            FileHandle.standardError.write(
                Data(
                    "xctidy: unknown --format '\(got)' (expected 'documentation', 'spec', or 'vitest')\n"
                        .utf8))
            exit(1)
        }
        style = parsed
        i += 1
    default:
        if !sawPositional {
            specsDir = args[i]
            sawPositional = true
        }
    }
    i += 1
}

let atoms = loadKnownAtoms(specsDir: specsDir)
let tty = isatty(fileno(stdout)) != 0

let engine = Engine(atoms: atoms, tty: tty, style: style)
while let line = readLine(strippingNewline: true) {
    engine.feedLine(line)
}
print(engine.finish(), terminator: "")

// Mirrors gorderly's `main.go` (`if failed > 0 { return 1 }`): reflect the
// underlying run's real outcome in our own exit code, so a caller that pipes
// straight into us (rather than using `set -o pipefail`) still sees failure.
// Before this, xctidy always exited 0 here regardless of engine.failures --
// see docs/COMMENTS.md for the full history of why that was unsafe.
exit(engine.failures.isEmpty ? 0 : 1)
