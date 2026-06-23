import XCTest
@testable import XcbeautifyFDKit

final class EngineTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempSpecsDir(_ files: [String: String]) -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcbeautify-fd-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            let url = dir.appendingPathComponent(name)
            try! contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    // Real chains pulled from next-caltrain-swift's Tests/*.swift, used to
    // prove both known comma-disambiguation edge cases: a parenthetical
    // aside, and a bare prose comma with no parens at all.
    private let goodTimesSwift = """
        describe("GoodTimes") {
            context("when 'today' is fixed via debugOverrideDotw") {
                context("and today is Saturday (6)") {
                    it("computes tomorrow as Sunday (0), wrapping the week") {}
                }
            }
        }
        """

    private let caltrainServiceSwift = """
        describe("CaltrainService") {
            describe("#routes(from:to:scheduleType:)") {
                context("for a direct diesel trip (Morgan Hill to Gilroy)") {
                    it("is not a transfer, since both endpoints are South County") {}
                }
                context("for a direct electric trip (San Francisco to San Jose Diridon)") {
                    it("is not a transfer") {}
                }
            }
            describe("#nextIndex(trips:minutes:)") {
                context("when given an empty trip list") {
                    it("returns nil") {}
                }
            }
        }
        """

    // MARK: - loadKnownAtoms

    func testLoadKnownAtomsScansDescribeContextItLiterals() {
        let dir = writeTempSpecsDir([
            "GoodTimesSpec.swift": goodTimesSwift,
            "CaltrainServiceSpec.swift": caltrainServiceSwift,
        ])
        let atoms = loadKnownAtoms(specsDir: dir)

        XCTAssertTrue(atoms.contains("GoodTimes"))
        XCTAssertTrue(atoms.contains("and today is Saturday (6)"))
        XCTAssertTrue(atoms.contains("computes tomorrow as Sunday (0), wrapping the week"))
        XCTAssertTrue(atoms.contains("is not a transfer, since both endpoints are South County"))
        XCTAssertTrue(atoms.contains("is not a transfer"))
    }

    func testLoadKnownAtomsUnescapesLiterals() {
        let dir = writeTempSpecsDir([
            "Quoted.swift": #"it("handles \"quoted\" text and a\ttab") {}"#
        ])
        let atoms = loadKnownAtoms(specsDir: dir)
        XCTAssertTrue(atoms.contains("handles \"quoted\" text and a\ttab"))
    }

    func testLoadKnownAtomsReturnsEmptySetForMissingDirectory() {
        let atoms = loadKnownAtoms(specsDir: "/nonexistent/path/for/xcbeautify-fd-tests")
        XCTAssertTrue(atoms.isEmpty)
    }

    // MARK: - splitPath disambiguation

    func testSplitPathResolvesBareProseCommaAsSingleLeaf() {
        let atoms: Set<String> = [
            "CaltrainService",
            "#routes(from:to:scheduleType:)",
            "for a direct diesel trip (Morgan Hill to Gilroy)",
            "is not a transfer, since both endpoints are South County",
        ]
        let name =
            "CaltrainService, #routes(from:to:scheduleType:), for a direct diesel trip (Morgan Hill to Gilroy), is not a transfer, since both endpoints are South County"
        let path = splitPath(name, atoms: atoms)
        XCTAssertEqual(
            path,
            [
                "CaltrainService",
                "#routes(from:to:scheduleType:)",
                "for a direct diesel trip (Morgan Hill to Gilroy)",
                "is not a transfer, since both endpoints are South County",
            ])
    }

    func testSplitPathResolvesParentheticalAside() {
        let atoms: Set<String> = [
            "GoodTimes",
            "when 'today' is fixed via debugOverrideDotw",
            "and today is Saturday (6)",
            "computes tomorrow as Sunday (0), wrapping the week",
        ]
        let name =
            "GoodTimes, when 'today' is fixed via debugOverrideDotw, and today is Saturday (6), computes tomorrow as Sunday (0), wrapping the week"
        let path = splitPath(name, atoms: atoms)
        XCTAssertEqual(path.last, "computes tomorrow as Sunday (0), wrapping the week")
        XCTAssertEqual(path.count, 4)
    }

    func testSplitPathFallsBackToHeuristicWhenAtomsEmpty() {
        let path = splitPath("foo, bar (baz, qux), last", atoms: [])
        XCTAssertEqual(path, ["foo", "bar (baz, qux)", "last"])
    }

    func testSplitPathFallsBackToHeuristicWhenAmbiguous() {
        // Two different valid decompositions exist against this atom set,
        // so splitPath can't trust either and must fall back.
        let atoms: Set<String> = ["a", "b, c", "a, b", "c"]
        let path = splitPath("a, b, c", atoms: atoms)
        XCTAssertEqual(path, ["a", "b", "c"])  // heuristic: plain top-level split
    }

    // MARK: - Engine: tree rendering

    func testSuiteHeaderIsEmittedWithBlankLineBefore() {
        let engine = Engine(atoms: [], tty: false)
        engine.feedLine("Test Suite 'GoodTimesSpec' started at 2026-06-22 10:00:00.000.")
        let output = engine.finish()
        XCTAssertTrue(output.contains("\nGoodTimesSpec\n"))
    }

    func testPassingCaseRendersDedupedNestedTree() {
        let atoms: Set<String> = [
            "CaltrainService",
            "#routes(from:to:scheduleType:)",
            "for a direct diesel trip (Morgan Hill to Gilroy)",
            "is not a transfer, since both endpoints are South County",
            "for a direct electric trip (San Francisco to San Jose Diridon)",
            "is not a transfer",
        ]
        let engine = Engine(atoms: atoms, tty: false)
        engine.feedLine(
            "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #routes(from:to:scheduleType:), for a direct diesel trip (Morgan Hill to Gilroy), is not a transfer, since both endpoints are South County]' passed (0.0033 seconds)."
        )
        engine.feedLine(
            "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #routes(from:to:scheduleType:), for a direct electric trip (San Francisco to San Jose Diridon), is not a transfer]' passed (0.0019 seconds)."
        )
        let output = engine.finish()

        // Shared prefix ("CaltrainService", "#routes(...)") printed once.
        XCTAssertEqual(output.components(separatedBy: "CaltrainService\n").count - 1, 1)
        XCTAssertEqual(
            output.components(separatedBy: "#routes(from:to:scheduleType:)\n").count - 1, 1)
        XCTAssertTrue(
            output.contains("is not a transfer, since both endpoints are South County"))
        XCTAssertTrue(output.contains("is not a transfer\n"))
    }

    func testFailingCaseIsAnnotatedAndFoldedIntoFailuresSection() {
        let atoms: Set<String> = [
            "CaltrainService",
            "#routes(from:to:scheduleType:)",
            "for a direct electric trip (San Francisco to San Jose Diridon)",
            "is not a transfer",
        ]
        let engine = Engine(atoms: atoms, tty: false)
        engine.feedLine(
            "/Users/woodie/workspace/next-caltrain-swift/Tests/CaltrainServiceSpec.swift:55: error: -[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #routes(from:to:scheduleType:), for a direct electric trip (San Francisco to San Jose Diridon), is not a transfer] : XCTAssertFalse failed - expected false, got true"
        )
        engine.feedLine(
            "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #routes(from:to:scheduleType:), for a direct electric trip (San Francisco to San Jose Diridon), is not a transfer]' failed (0.0019 seconds)."
        )
        let output = engine.finish()

        XCTAssertTrue(output.contains("is not a transfer (FAILED - 1)"))
        XCTAssertTrue(output.contains("Failures:"))
        XCTAssertTrue(output.contains("1) CaltrainService #routes(from:to:scheduleType:)"))
        XCTAssertTrue(output.contains("XCTAssertFalse failed - expected false, got true"))
        XCTAssertTrue(
            output.contains("# /Users/woodie/workspace/next-caltrain-swift/Tests/CaltrainServiceSpec.swift:55")
        )
        XCTAssertEqual(engine.failures.count, 1)
    }

    func testSkippedCaseIsAnnotated() {
        let engine = Engine(atoms: ["returns nil"], tty: false)
        engine.feedLine(
            "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #nextIndex(trips:minutes:), when given an empty trip list, returns nil]' skipped (0.0001 seconds)."
        )
        let output = engine.finish()
        XCTAssertTrue(output.contains("returns nil (SKIPPED)"))
    }

    // MARK: - Engine: noise suppression / safety net

    func testSuppressesRoutineBuildNoise() {
        let engine = Engine(atoms: [], tty: false)
        engine.feedLine("CompileSwift normal x86_64 /path/to/Foo.swift")
        engine.feedLine("Ld /path/to/NextCaltrainTests.xctest/NextCaltrainTests normal")
        let output = engine.finish()
        XCTAssertEqual(output, "\n")
    }

    func testSuppressesExecutedSummaryLines() {
        let engine = Engine(atoms: [], tty: false)
        engine.feedLine(" Executed 4 tests, with 1 failure (0 unexpected) in 0.007 (0.015) seconds")
        XCTAssertEqual(engine.finish(), "\n")
    }

    func testPassesThroughGenuineCompileErrorsAsASafetyNet() {
        let engine = Engine(atoms: [], tty: false)
        engine.feedLine("/path/to/Foo.swift:12:5: error: cannot find type 'Bar' in scope")
        let output = engine.finish()
        XCTAssertTrue(output.contains("cannot find type 'Bar' in scope"))
    }

    // MARK: - Color output

    func testColorCodesOmittedWhenNotTTY() {
        let engine = Engine(atoms: [], tty: false)
        engine.feedLine(
            "Test Case '-[Suite foo]' passed (0.001 seconds)."
        )
        XCTAssertFalse(engine.finish().contains("\u{1B}["))
    }

    func testColorCodesPresentWhenTTY() {
        let engine = Engine(atoms: [], tty: true)
        engine.feedLine(
            "Test Case '-[Suite foo]' passed (0.001 seconds)."
        )
        XCTAssertTrue(engine.finish().contains("\u{1B}[32m"))
    }
}
