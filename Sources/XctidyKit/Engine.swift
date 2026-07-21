import Foundation

// MARK: - Raw xcodebuild line matchers

// caseStarted/caseFinished's class capture uses \S+ (not xcpretty's ambiguous (.*) (.*)) -- class names never contain spaces. See docs/COMMENTS.md.

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
    case brightGreen = "92"
    case yellow = "33"
    case cyan = "36"
    case gray = "90"
}

/// Controls per-leaf label rendering: `.classic` (default, glyph + time), `.doc` (RSpec `-fd` clone), `.spec` (Mocha/Jest clone), `.vitest` (Vitest's own tree clone, gorderly's `-fv` counterpart) -- the first three share one identical xcbeautify-style closing footer; `.vitest` closes with Vitest's own Tests/Duration shape instead. See docs/COMMENTS.md.
public enum RenderStyle: Equatable {
    case classic
    case doc
    case spec
    case vitest
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

    /// Feeds one raw `xcodebuild test` output line; suppresses routine build-phase noise but passes through anything containing "error:" or a build-failure marker verbatim. See docs/COMMENTS.md.
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
            // group(4) is the per-test time; only .classic renders it per-leaf (see labelForPassed/labelForSkipped/labelForFailed). See docs/COMMENTS.md.
            let time = m.group(4, in: line)
            renderCase(path: path, state: state, time: time)
            curFailureLines = []
            return
        }
        if Matchers.caseStarted.firstMatch(in: line) != nil {
            return  // pure bookkeeping; the tree is rendered from caseFinished
        }
        if let m = Matchers.executedSummary.firstMatch(in: line) {
            // Last executedSummary line wins -- XCTest finishes inner scopes before outer ones, so the final match is always the outermost total. See docs/COMMENTS.md.
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

    // .classic's "(N seconds)" suffix, colored to match its glyph -- mirrors xcbeautify's own .coloredTime().
    private func timedSuffix(_ color: AnsiColor, _ time: String?) -> String {
        guard let time else { return "" }
        return " (\(colorize(color, time)) seconds)"
    }

    // vitestDurationParts mirrors gorderly's formatVitestDurationParts, itself mirroring Vitest's own formatTime (utils.ts): whole milliseconds under 1000ms, seconds to two decimals at or above -- same seconds-in, (number, unit)-out conversion gorderly does for `go test -v`'s equivalent timing.
    private func vitestDurationParts(_ time: String?) -> (number: String, unit: String)? {
        guard let time, let seconds = Double(time) else { return nil }
        let milliseconds = seconds * 1000
        if milliseconds > 1000 {
            return (String(format: "%.2f", milliseconds / 1000), "s")
        }
        return (String(Int(milliseconds.rounded())), "ms")
    }

    private func labelForPassed(name: String, time: String?) -> String {
        switch style {
        case .classic:
            return "\(colorize(.green, "✔")) \(name)\(timedSuffix(.green, time))"
        case .doc:
            return colorize(.green, name)
        case .spec:
            return colorize(.green, "✔") + " " + colorize(.gray, name)
        case .vitest:
            // Name stays uncolored (not gray) and the duration is two-toned (plain green number, lighter brightGreen unit) -- matches a real `vitest run`, confirmed rather than assumed. See gorderly's render.go.
            guard let parts = vitestDurationParts(time) else {
                return "\(colorize(.green, "✓")) \(name)"
            }
            let number = colorize(.green, parts.number)
            let unit = colorize(.brightGreen, parts.unit)
            return "\(colorize(.green, "✓")) \(name) \(number)\(unit)"
        }
    }

    private func labelForSkipped(name: String, time: String?) -> String {
        pendingCount += 1
        switch style {
        case .classic:
            // classic signals skips by glyph (⊘) + color only, not text -- see -fd/-fs for spelled-out "(SKIPPED)"/"(PENDING)" labels. See docs/COMMENTS.md.
            return "\(colorize(.cyan, "⊘")) \(name)\(timedSuffix(.cyan, time))"
        case .doc:
            return colorize(.yellow, "\(name) (PENDING)")
        case .spec:
            return colorize(.cyan, "- \(name) (SKIPPED)")
        case .vitest:
            // Vitest's own skipped glyph is a dim gray ↓, no time shown -- skipped tests never ran, so there's nothing to time.
            return colorize(.gray, "↓ \(name)")
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
            // Keeps the "(FAILED - N)" Failures cross-reference alongside the original glyph + per-test time. See docs/COMMENTS.md.
            return "\(colorize(.red, "✖")) \(name) (FAILED - \(num))\(timedSuffix(.red, time))"
        case .doc:
            return colorize(.red, "\(name) (FAILED - \(num))")
        case .spec:
            return colorize(.red, "✗ \(name) (FAILED - \(num))")
        case .vitest:
            // No inline "(FAILED - N)" -- Vitest's own tree doesn't number failures inline either; the trailing Failures: section still cross-references by number, same as gorderly's -fv.
            guard let parts = vitestDurationParts(time) else {
                return colorize(.red, "× \(name)")
            }
            return colorize(.red, "× \(name) \(parts.number)\(parts.unit)")
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
            // Gated on exampleCount > 0 so noise-only input still finishes as just "\n", matching xcodebuild's own behavior of only printing "** TEST SUCCEEDED **" after a real test run. See docs/COMMENTS.md.
            emit()
            if style == .vitest {
                emitVitestFooter()
            } else {
                let succeeded = failures.isEmpty
                let color: AnsiColor = succeeded ? .green : .red
                emit(colorize(color, succeeded ? "Test Succeeded" : "Test Failed"))
                var summary = "Tests Passed: \(failures.count) failed, \(pendingCount) skipped, \(exampleCount) total"
                if let t = lastTestTimeText {
                    summary += " (\(t) seconds)"
                }
                emit(colorize(color, summary))
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    // emitVitestFooter mirrors gorderly's vitestSummaryLine (label right-justified to 11 columns, then "N failed | M passed | K skipped (total)"), but intentionally omits Vitest's "Test Files" line -- XCTest's own Test Suite nesting (a per-class suite wrapped in an "All tests"/"Selected tests" aggregate) isn't verified against real xcodebuild output here, so a suite-level count risks over-counting wrapper suites as their own files; gorderly's one-line-per-Go-package had no such ambiguity. Fill this in once checked against a real xcodebuild run.
    private func emitVitestFooter() {
        let passed = exampleCount - failures.count - pendingCount
        emit(vitestSummaryLine(
            "Tests", failed: failures.count, passed: passed, skipped: pendingCount, total: exampleCount))
        if let parts = vitestDurationParts(lastTestTimeText) {
            emit("\(padLabel("Duration"))  \(parts.number)\(parts.unit)")
        }
    }

    // padLabel right-justifies to 11 columns, matching Vitest's own padSummaryTitle (str.padStart(11)) -- confirmed against Vitest's reporter source, not guessed. See gorderly's vitestSummaryLine.
    private func padLabel(_ label: String) -> String {
        String(repeating: " ", count: max(0, 11 - label.count)) + label
    }

    private func vitestSummaryLine(_ label: String, failed: Int, passed: Int, skipped: Int, total: Int) -> String {
        var parts: [String] = []
        if failed > 0 { parts.append(colorize(.red, "\(failed) failed")) }
        if passed > 0 { parts.append(colorize(.green, "\(passed) passed")) }
        if skipped > 0 { parts.append(colorize(.gray, "\(skipped) skipped")) }
        if parts.isEmpty { parts.append("0 passed") }
        return "\(padLabel(label))  \(parts.joined(separator: " | ")) (\(total))"
    }
}
