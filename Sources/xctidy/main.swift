import Foundation
import XctidyKit

#if canImport(Glibc)
    import Glibc
#else
    import Darwin
#endif

// Usage: xcodebuild test ... | xctidy [-fd|-fs|--format documentation|--format spec] [path-to-Tests-dir]
//
// Reads raw xcodebuild output from stdin -- the same protocol xcpretty and
// xcbeautify both parse -- and writes a nested tree to stdout. No
// xcbeautify/xcpretty installation required; xctidy is a drop-in
// replacement formatter, not a post-processor chained after either of them
// (see docs/HOW_IT_WORKS.md, "Where this fits in a fastlane pipeline").
//
//   (no flag)  default: glyph + "name (N seconds)" per leaf ("✔"/"⊘"/"✖",
//              colored), failures additionally keep "(FAILED - N)".
//   -fd        an actual clone of real RSpec's `-fd`/documentation
//              formatter's leaf rendering: plain colored name, no glyph, no
//              per-test time; pending examples are yellow and say
//              "(PENDING)". Long form: --format documentation.
//   -fs        the more common look -- green "✔ name" (name dimmed gray) for
//              passes, red "✗ name (FAILED - 1)" for failures, cyan
//              "- name (SKIPPED)" for skips. Same convention as Mocha's
//              default `spec` reporter or Jest's. Long form: --format spec.
//
// All three styles end with the exact same run-results footer, lifted
// verbatim from real xcbeautify -- a green "Test Succeeded"/red
// "Test Failed" headline, then "Tests Passed: X failed, Y skipped, Z total
// (N seconds)". Neither -fd nor -fs additionally prints RSpec's/Mocha's own
// native run summary on top of that -- see docs/HOW_IT_WORKS.md,
// "Output styles".

var style: RenderStyle = .classic
var specsDir = "."
var sawPositional = false

func parseStyle(_ raw: String) -> RenderStyle? {
    switch raw {
    case "documentation": return .fd
    case "spec": return .spec
    default: return nil
    }
}

var args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    switch args[i] {
    case "-fd":
        style = .fd
    case "-fs":
        style = .spec
    case "--format":
        guard i + 1 < args.count, let parsed = parseStyle(args[i + 1]) else {
            let got = i + 1 < args.count ? args[i + 1] : "<missing>"
            FileHandle.standardError.write(
                Data(
                    "xctidy: unknown --format '\(got)' (expected 'documentation' or 'spec')\n"
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
