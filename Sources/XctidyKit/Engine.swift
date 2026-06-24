import Foundation

// xctidy's core engine.
//
// Parses RAW `xcodebuild test` output directly -- the same textual protocol
// xcpretty's `parser.rb` and xcbeautify both regex-match (there is no formal
// API; this *is* the API). No dependency on xcbeautify or xcpretty being
// installed.
//
// Quick promotes the full comma-joined `describe`/`context`/`it` text
// (literal prose, commas and all) to be the XCTest selector name, so a raw
// `Test Case '-[Class full, prose, name]'` line can't be split on every
// comma -- some commas are nesting separators, some are just commas in the
// prose. This engine disambiguates by cross-referencing the literal
// `describe(...)`/`context(...)`/`it(...)` strings found in the project's
// `.swift` files under `Tests/` (see `loadKnownAtoms`), falling back to a
// paren-depth-aware heuristic split when that dictionary can't resolve the
// name uniquely.

// MARK: - Raw xcodebuild line matchers
//
// Mirrors xcpretty's parser.rb matchers. One deliberate improvement: the
// suite/class capture group uses `\S+` (no whitespace) instead of xcpretty's
// ambiguous `(.*) (.*)`, since Swift/Obj-C class names never contain spaces.
// That cleanly separates "ClassName" from "full prose comma-joined name" --
// xcpretty's own pattern just greedily grabs everything as a flat string,
// which is fine for its flat failure list but unusable for a nested tree.

enum Matchers {
    static let suiteStarted = try! NSRegularExpression(
        pattern: #"^Test Suite '(.+)' started at (.+)\.$"#)
    static let suiteFinished = try! NSRegularExpression(
        pattern: #"^Test Suite '(.+)' (passed|failed) at (.+)\.$"#)
    static let caseStarted = try! NSRegularExpression(
        pattern: #"^Test Case '-\[(\S+) (.+)\]' started\.$"#)
    static let caseFinished = try! NSRegularExpression(
        pattern: #"^Test Case '-\[(\S+) (.+)\]' (passed|failed|skipped) \(([\d.]+) seconds\)\.$"#)
    static let failureDetail = try! NSRegularExpression(
        pattern: #"^(.+:\d+): error: [+-]\[(\S+) (.+)\] : (.*)$"#)
    static let executedSummary = try! NSRegularExpression(
        pattern: #"^\s*Executed \d+ tests?, with \d+ failures? \(\d+ unexpected\) in ([\d.]+) \([\d.]+\) seconds$"#)
    static let atomCall = try! NSRegularExpression(
        pattern: #"\b(?:describe|context|it)\(\s*"((?:[^"\\]|\\.)*)""#)
}

extension NSRegularExpression {
    func firstMatch(in str: String) -> NSTextCheckingResult? {
        firstMatch(in: str, range: NSRange(location: 0, length: (str as NSString).length))
    }
}

extension NSTextCheckingResult {
    func group(_ idx: Int, in original: String) -> String? {
        guard idx < numberOfRanges else { return nil }
        let r = range(at: idx)
        guard r.location != NSNotFound else { return nil }
        return (original as NSString).substring(with: r)
    }
}

// MARK: - Color output

enum AnsiColor: String {
    case red = "31"
    case green = "32"
    case yellow = "33"
    case cyan = "36"
    case gray = "90"
}

/// `.classic` (default): every leaf gets xcbeautify's own "✔"/"⊘"/"✖" glyph
/// plus the per-test "(N seconds)" xcodebuild reports, both colored
/// (green/cyan/red); a failed leaf also keeps this project's "(FAILED - N)"
/// cross-reference into the Failures section (see docs/HOW_IT_WORKS.md,
/// "Failure folding").
///
/// `.doc` clones real RSpec's `-fd`/documentation formatter's *leaf*
/// rendering: a plain colored name with no glyph and no per-test time,
/// and pending examples are yellow and say "(PENDING)" (RSpec's own
/// wording, not Xcode's "SKIPPED").
///
/// `.spec` clones the more common convention used by reporters like Mocha's
/// default `spec` reporter or Jest, again for *leaf* rendering only: a
/// green "✔" with the passing test's name dimmed to gray (de-emphasized,
/// since passes aren't where attention is needed), a red
/// "✗ name (FAILED - N)" for failures, and a cyan "- name (SKIPPED)" for
/// skips.
///
/// All three styles end with exactly the same thing: real xcbeautify's own
/// run-results footer -- a green "Test Succeeded" (or red "Test Failed")
/// headline, then "Tests Passed: X failed, Y skipped, Z total (N seconds)".
/// `.doc` and `.spec` don't additionally print RSpec's/Mocha's own native run
/// summary ("Finished in.../X examples", "N passing (Ttime)") -- an earlier
/// version of this tool stacked that native summary before the xcbeautify
/// footer, but seeing all three styles' real output side by side made that
/// look like three different conventions for the same information instead
/// of one shared, unambiguous ending. See `finish()`'s trailing
/// `if exampleCount > 0` block.
public enum RenderStyle: Equatable {
    case classic
    case doc
    case spec
}

// MARK: - Failures

public struct EngineFailure {
    public let num: Int
    public let full: [String]
    public let message: String
    public let location: String
}

// MARK: - Engine

public final class Engine {
    private let atoms: Set<String>
    private let tty: Bool
    private let style: RenderStyle
    private var lastPath: [String] = []
    private var curFailureLines: [(location: String, reason: String)] = []
    private(set) public var failures: [EngineFailure] = []
    private var out: [String] = []
    private var exampleCount = 0
    private var pendingCount = 0
    private var lastTestTimeText: String?

    public init(atoms: Set<String>, tty: Bool, style: RenderStyle = .classic) {
        self.atoms = atoms
        self.tty = tty
        self.style = style
    }

    private func colorize(_ color: AnsiColor, _ txt: String) -> String {
        guard tty else { return txt }
        return "\u{1B}[\(color.rawValue)m\(txt)\u{1B}[0m"
    }

    private func emit(_ txt: String = "") {
        out.append(txt)
    }

    /// Feed one line of raw `xcodebuild test` output. Lines that are part of
    /// the test protocol are consumed and re-rendered as the nested tree;
    /// everything else (compiles, links, codesign -- the build-phase noise
    /// xcpretty/xcbeautify spend most of their matchers on) is suppressed,
    /// *except* for anything containing "error:" or a fatal/build-failed
    /// marker, which is passed through verbatim so a real build failure is
    /// never silently hidden. This tool is scoped to test output, the same
    /// way ginkgo-fd doesn't bother reformatting `go build`'s own output.
    public func feedLine(_ line: String) {
        if let m = Matchers.suiteStarted.firstMatch(in: line), let name = m.group(1, in: line) {
            emit()
            emit(name)
            return
        }
        if Matchers.suiteFinished.firstMatch(in: line) != nil {
            return
        }
        if let m = Matchers.failureDetail.firstMatch(in: line),
            let location = m.group(1, in: line), let reason = m.group(4, in: line) {
            curFailureLines.append((location: location, reason: reason))
            return
        }
        if let m = Matchers.caseFinished.firstMatch(in: line),
            let name = m.group(2, in: line), let state = m.group(3, in: line) {
            let path = splitPath(name, atoms: atoms)
            // group(4) is the per-test "(N seconds)" xcodebuild reports for
            // every case regardless of outcome -- .classic surfaces it
            // directly (see RenderStyle doc comment); .doc/.spec don't use it
            // per-leaf, only lastTestTimeText's run-level total.
            let time = m.group(4, in: line)
            renderCase(path: path, state: state, time: time)
            curFailureLines = []
            return
        }
        if Matchers.caseStarted.firstMatch(in: line) != nil {
            return  // pure bookkeeping; the tree is rendered from caseFinished
        }
        if let m = Matchers.executedSummary.firstMatch(in: line) {
            // Suppressed from passthrough either way; we keep the captured
            // time for the shared closing footer's "(N seconds)" annotation
            // in finish(), regardless of style. There's one of these per
            // nesting level (per-class, per-bundle, "All tests"); the last
            // one wins, which is always the outermost/final total since
            // XCTest finishes inner scopes before outer ones.
            lastTestTimeText = m.group(1, in: line)
            return
        }
        if line.contains("error:") || line.contains("fatal error:")
            || line.contains("** BUILD FAILED **") || line.contains("** TEST FAILED **") {
            emit(line)
            return
        }
        // else: suppress routine build-phase noise.
    }

    private func renderCase(path: [String], state: String, time: String?) {
        exampleCount += 1
        var shared = 0
        for (a, b) in zip(path, lastPath) {
            if a != b { break }
            shared += 1
        }
        if path.count > 1 {
            for depth in shared..<(path.count - 1) {
                emit(String(repeating: "  ", count: depth + 1) + path[depth])
            }
        }
        let leafDepth = path.count - 1
        let name = path[path.count - 1]

        let label: String
        switch state {
        case "passed":
            label = labelForPassed(name: name, time: time)
        case "skipped":
            label = labelForSkipped(name: name, time: time)
        case "failed":
            label = labelForFailed(name: name, path: path, time: time)
        default:
            label = name
        }

        emit(String(repeating: "  ", count: leafDepth + 1) + label)
        lastPath = path
    }

    // .classic's "(N seconds)" suffix, colored to match its glyph -- mirrors
    // xcbeautify's own .coloredTime().
    private func timedSuffix(_ color: AnsiColor, _ time: String?) -> String {
        guard let time else { return "" }
        return " (\(colorize(color, time)) seconds)"
    }

    private func labelForPassed(name: String, time: String?) -> String {
        switch style {
        case .classic:
            return "\(colorize(.green, "✔")) \(name)\(timedSuffix(.green, time))"
        case .doc:
            return colorize(.green, name)
        case .spec:
            return colorize(.green, "✔") + " " + colorize(.gray, name)
        }
    }

    private func labelForSkipped(name: String, time: String?) -> String {
        pendingCount += 1
        switch style {
        case .classic:
            // No "(SKIPPED)" text suffix here, deliberately -- .classic
            // distinguishes skips from passes by glyph (⊘ vs ✔) and color
            // alone. -fd and -fs both spell it out in words; reach for those
            // if a glyph-only signal isn't enough in your terminal/font.
            return "\(colorize(.cyan, "⊘")) \(name)\(timedSuffix(.cyan, time))"
        case .doc:
            return colorize(.yellow, "\(name) (PENDING)")
        case .spec:
            return colorize(.cyan, "- \(name) (SKIPPED)")
        }
    }

    private func labelForFailed(name: String, path: [String], time: String?) -> String {
        let num = failures.count + 1
        let message = curFailureLines.map { $0.reason }.joined(separator: "\n")
        let location = curFailureLines.first?.location ?? "?"
        failures.append(
            EngineFailure(
                num: num,
                full: path,
                message: message.isEmpty ? "(no failure detail captured)" : message,
                location: location))
        switch style {
        case .classic:
            // Keeps the "(FAILED - N)" Failures cross-reference (the
            // headline improvement raw-protocol parsing makes possible)
            // alongside the original's glyph + per-test time.
            return "\(colorize(.red, "✖")) \(name) (FAILED - \(num))\(timedSuffix(.red, time))"
        case .doc:
            return colorize(.red, "\(name) (FAILED - \(num))")
        case .spec:
            return colorize(.red, "✗ \(name) (FAILED - \(num))")
        }
    }

    public func finish() -> String {
        if !failures.isEmpty {
            emit()
            emit("Failures:")
            for f in failures {
                emit()
                emit("  \(f.num)) \(f.full.joined(separator: " "))")
                for line in f.message.split(separator: "\n", omittingEmptySubsequences: false) {
                    emit("     \(line)")
                }
                emit("     # \(f.location)")
            }
        }
        if exampleCount > 0 {
            // Real xcbeautify's own run-results footer, lifted verbatim
            // from a genuine `xcodebuild test` run. It's the *only* run
            // summary any style prints -- .doc and .spec render their leaves
            // differently above (see RenderStyle's doc comment) but don't
            // get their own native RSpec-/Mocha-style run summary on top of
            // it, so there's exactly one footer convention to read
            // regardless of which -fd/-fs/--format flag produced the tree
            // above it. A green/red headline, then a "Tests Passed:" line
            // that -- despite the name -- always lists all three counts,
            // not just passes. Gated on exampleCount > 0 so noise-only
            // input (no Test Case lines at all) still finishes as just
            // "\n", matching xcodebuild's own behavior -- it only prints
            // "** TEST SUCCEEDED **" when a test run actually happened,
            // never on a noise-only/build-only invocation.
            emit()
            let succeeded = failures.isEmpty
            let color: AnsiColor = succeeded ? .green : .red
            emit(colorize(color, succeeded ? "Test Succeeded" : "Test Failed"))
            var summary = "Tests Passed: \(failures.count) failed, \(pendingCount) skipped, \(exampleCount) total"
            if let t = lastTestTimeText {
                summary += " (\(t) seconds)"
            }
            emit(colorize(color, summary))
        }
        return out.joined(separator: "\n") + "\n"
    }
}
