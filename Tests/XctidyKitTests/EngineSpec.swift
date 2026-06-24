import Quick
import Nimble
import Foundation
@testable import XctidyKit

// MARK: - Fixtures

// Real chains pulled from next-caltrain-swift's .swift files under Tests/, used to prove
// both known comma-disambiguation edge cases: a parenthetical aside, and a
// bare prose comma with no parens at all.
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

private func writeTempSpecsDir(_ files: [String: String]) -> String {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("xctidy-tests-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for (name, contents) in files {
        let url = dir.appendingPathComponent(name)
        try! contents.write(to: url, atomically: true, encoding: .utf8)
    }
    return dir.path
}

final class EngineSpec: QuickSpec {
    override static func spec() {

        describe("loadKnownAtoms") {
            it("scans describe/context/it literals out of the given directory") {
                let dir = writeTempSpecsDir([
                    "GoodTimesSpec.swift": goodTimesSwift,
                    "CaltrainServiceSpec.swift": caltrainServiceSwift,
                ])
                let atoms = loadKnownAtoms(specsDir: dir)

                expect(atoms).to(contain("GoodTimes"))
                expect(atoms).to(contain("and today is Saturday (6)"))
                expect(atoms).to(contain("computes tomorrow as Sunday (0), wrapping the week"))
                expect(atoms).to(contain("is not a transfer, since both endpoints are South County"))
                expect(atoms).to(contain("is not a transfer"))
            }

            it("unescapes quoted/tab literals") {
                let dir = writeTempSpecsDir([
                    "Quoted.swift": #"it("handles \"quoted\" text and a\ttab") {}"#
                ])
                let atoms = loadKnownAtoms(specsDir: dir)
                expect(atoms).to(contain("handles \"quoted\" text and a\ttab"))
            }

            it("returns an empty set for a missing directory") {
                let atoms = loadKnownAtoms(specsDir: "/nonexistent/path/for/xctidy-tests")
                expect(atoms).to(beEmpty())
            }
        }

        describe("splitPath") {
            context("disambiguation against known atoms") {
                it("resolves a bare prose comma as a single leaf") {
                    let atoms: Set<String> = [
                        "CaltrainService",
                        "#routes(from:to:scheduleType:)",
                        "for a direct diesel trip (Morgan Hill to Gilroy)",
                        "is not a transfer, since both endpoints are South County",
                    ]
                    let name =
                        "CaltrainService, #routes(from:to:scheduleType:), for a direct diesel trip (Morgan Hill to Gilroy), is not a transfer, since both endpoints are South County"
                    let path = splitPath(name, atoms: atoms)
                    expect(path).to(equal([
                        "CaltrainService",
                        "#routes(from:to:scheduleType:)",
                        "for a direct diesel trip (Morgan Hill to Gilroy)",
                        "is not a transfer, since both endpoints are South County",
                    ]))
                }

                it("resolves a parenthetical aside") {
                    let atoms: Set<String> = [
                        "GoodTimes",
                        "when 'today' is fixed via debugOverrideDotw",
                        "and today is Saturday (6)",
                        "computes tomorrow as Sunday (0), wrapping the week",
                    ]
                    let name =
                        "GoodTimes, when 'today' is fixed via debugOverrideDotw, and today is Saturday (6), computes tomorrow as Sunday (0), wrapping the week"
                    let path = splitPath(name, atoms: atoms)
                    expect(path.last).to(equal("computes tomorrow as Sunday (0), wrapping the week"))
                    expect(path.count).to(equal(4))
                }
            }

            context("when it can't trust the atom dictionary") {
                it("falls back to the heuristic when atoms is empty") {
                    let path = splitPath("foo, bar (baz, qux), last", atoms: [])
                    expect(path).to(equal(["foo", "bar (baz, qux)", "last"]))
                }

                it("falls back to the heuristic when the decomposition is ambiguous") {
                    // Two different valid decompositions exist against this atom
                    // set, so splitPath can't trust either and must fall back.
                    let atoms: Set<String> = ["a", "b, c", "a, b", "c"]
                    let path = splitPath("a, b, c", atoms: atoms)
                    expect(path).to(equal(["a", "b", "c"]))  // heuristic: plain top-level split
                }
            }
        }

        describe("Engine") {
            context("tree rendering") {
                it("emits the suite header with a blank line before it") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("Test Suite 'GoodTimesSpec' started at 2026-06-22 10:00:00.000.")
                    let output = engine.finish()
                    expect(output).to(contain("\nGoodTimesSpec\n"))
                }

                it("renders a deduped nested tree for passing cases") {
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
                    expect(output.components(separatedBy: "CaltrainService\n").count - 1).to(equal(1))
                    expect(output.components(separatedBy: "#routes(from:to:scheduleType:)\n").count - 1).to(
                        equal(1))
                    expect(output).to(contain("is not a transfer, since both endpoints are South County"))
                    // Distinguishes the second (shorter) leaf from the first by its
                    // own elapsed time, now that classic appends "(N seconds)".
                    expect(output).to(contain("is not a transfer (0.0019 seconds)"))
                }

                it("annotates a failing case and folds it into the Failures section") {
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

                    expect(output).to(contain("is not a transfer (FAILED - 1)"))
                    expect(output).to(contain("Failures:"))
                    expect(output).to(contain("1) CaltrainService #routes(from:to:scheduleType:)"))
                    expect(output).to(contain("XCTAssertFalse failed - expected false, got true"))
                    expect(output).to(
                        contain(
                            "# /Users/woodie/workspace/next-caltrain-swift/Tests/CaltrainServiceSpec.swift:55")
                    )
                    expect(engine.failures.count).to(equal(1))
                }

                it("annotates a skipped case") {
                    let engine = Engine(atoms: ["returns nil"], tty: false)
                    engine.feedLine(
                        "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #nextIndex(trips:minutes:), when given an empty trip list, returns nil]' skipped (0.0001 seconds)."
                    )
                    let output = engine.finish()
                    // classic distinguishes skips by glyph + color, not text --
                    // see "classic style" below for why there's no "(SKIPPED)".
                    expect(output).to(contain("⊘ returns nil (0.0001 seconds)"))
                }
            }

            context("noise suppression / safety net") {
                it("suppresses routine build noise") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("CompileSwift normal x86_64 /path/to/Foo.swift")
                    engine.feedLine("Ld /path/to/NextCaltrainTests.xctest/NextCaltrainTests normal")
                    let output = engine.finish()
                    expect(output).to(equal("\n"))
                }

                it("suppresses the executed-summary line") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine(" Executed 4 tests, with 1 failure (0 unexpected) in 0.007 (0.015) seconds")
                    expect(engine.finish()).to(equal("\n"))
                }

                it("passes through genuine compile errors as a safety net") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("/path/to/Foo.swift:12:5: error: cannot find type 'Bar' in scope")
                    let output = engine.finish()
                    expect(output).to(contain("cannot find type 'Bar' in scope"))
                }
            }

            context("color output") {
                it("omits color codes when not a TTY") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    expect(engine.finish()).toNot(contain("\u{1B}["))
                }

                it("includes color codes when a TTY") {
                    let engine = Engine(atoms: [], tty: true)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    expect(engine.finish()).to(contain("\u{1B}[32m"))
                }
            }

            context("classic style (default, swift.txt fidelity)") {
                it("renders a passed case with a checkmark glyph and its elapsed time") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.007 seconds).")
                    expect(engine.finish()).to(contain("✔ foo (0.007 seconds)"))
                }

                it("renders a skipped case with a dash-circle glyph and elapsed time, no text marker") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("Test Case '-[Suite foo]' skipped (0.001 seconds).")
                    let output = engine.finish()
                    expect(output).to(contain("⊘ foo (0.001 seconds)"))
                    expect(output).toNot(contain("SKIPPED"))
                }

                it("renders a failed case with a cross glyph, the FAILED cross-reference, and elapsed time") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("/path/to/Foo.swift:1: error: -[Suite foo] : it broke")
                    engine.feedLine("Test Case '-[Suite foo]' failed (0.0019 seconds).")
                    let output = engine.finish()
                    expect(output).to(contain("✖ foo (FAILED - 1) (0.0019 seconds)"))
                    expect(engine.failures.count).to(equal(1))
                }

                it("colors the glyph and elapsed time green when a TTY") {
                    let engine = Engine(atoms: [], tty: true)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    expect(engine.finish()).to(contain("\u{1B}[32m"))
                }

                it("appends xcbeautify's 'Test Succeeded' / 'Tests Passed' footer") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    engine.feedLine(" Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.002) seconds")
                    let output = engine.finish()
                    expect(output).to(contain("Test Succeeded"))
                    expect(output).to(contain("Tests Passed: 0 failed, 0 skipped, 1 total (0.001 seconds)"))
                }

                it("switches to 'Test Failed' and counts the failure in the footer") {
                    let engine = Engine(atoms: [], tty: false)
                    engine.feedLine("/path/to/Foo.swift:1: error: -[Suite foo] : it broke")
                    engine.feedLine("Test Case '-[Suite foo]' failed (0.0019 seconds).")
                    engine.feedLine(" Executed 1 test, with 1 failure (0 unexpected) in 0.0019 (0.003) seconds")
                    let output = engine.finish()
                    expect(output).to(contain("Test Failed"))
                    expect(output).to(contain("Tests Passed: 1 failed, 0 skipped, 1 total (0.0019 seconds)"))
                }
            }

            context("spec style") {
                it("renders a passed case with a checkmark and a gray name") {
                    let engine = Engine(atoms: [], tty: false, style: .spec)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    expect(engine.finish()).to(contain("✔ foo"))
                }

                it("renders a failed case with a cross and keeps the FAILED marker") {
                    let engine = Engine(atoms: [], tty: false, style: .spec)
                    engine.feedLine("/path/to/Foo.swift:1: error: -[Suite foo] : it broke")
                    engine.feedLine("Test Case '-[Suite foo]' failed (0.001 seconds).")
                    let output = engine.finish()
                    expect(output).to(contain("✗ foo (FAILED - 1)"))
                    expect(engine.failures.count).to(equal(1))
                }

                it("renders a skipped case with a dash and keeps the SKIPPED marker") {
                    let engine = Engine(atoms: [], tty: false, style: .spec)
                    engine.feedLine("Test Case '-[Suite foo]' skipped (0.001 seconds).")
                    expect(engine.finish()).to(contain("- foo (SKIPPED)"))
                }

                it("dims the name in gray (90) when a TTY") {
                    let engine = Engine(atoms: [], tty: true, style: .spec)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    expect(engine.finish()).to(contain("\u{1B}[90m"))
                }

                it("ends with the shared xcbeautify-style footer, not Mocha's own 'N passing' summary") {
                    let engine = Engine(atoms: [], tty: false, style: .spec)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    engine.feedLine("Test Case '-[Suite bar]' skipped (0.001 seconds).")
                    engine.feedLine(" Executed 2 tests, with 0 failures (0 unexpected) in 0.026 (0.030) seconds")
                    let output = engine.finish()
                    expect(output).toNot(contain("passing"))
                    expect(output).toNot(contain("pending"))
                    expect(output).to(contain("Test Succeeded"))
                    expect(output).to(contain("Tests Passed: 0 failed, 1 skipped, 2 total (0.026 seconds)"))
                }
            }

            context("rspec fidelity (--fd)") {
                it("renders skipped examples with RSpec's (PENDING) wording") {
                    let engine = Engine(atoms: ["returns nil"], tty: false, style: .doc)
                    engine.feedLine(
                        "Test Case '-[NextCaltrainTests.CaltrainServiceSpec CaltrainService, #nextIndex(trips:minutes:), when given an empty trip list, returns nil]' skipped (0.0001 seconds)."
                    )
                    expect(engine.finish()).to(contain("returns nil (PENDING)"))
                }

                it("colors pending examples yellow, not cyan, when a TTY") {
                    let engine = Engine(atoms: [], tty: true, style: .doc)
                    engine.feedLine("Test Case '-[Suite foo]' skipped (0.001 seconds).")
                    expect(engine.finish()).to(contain("\u{1B}[33m"))
                }

                it("ends with the shared xcbeautify-style footer, not RSpec's own 'Finished in' summary") {
                    let engine = Engine(atoms: [], tty: false, style: .doc)
                    engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                    engine.feedLine("Test Case '-[Suite bar]' skipped (0.001 seconds).")
                    engine.feedLine(" Executed 2 tests, with 0 failures (0 unexpected) in 0.026 (0.030) seconds")
                    let output = engine.finish()
                    expect(output).toNot(contain("Finished in"))
                    expect(output).toNot(contain("examples,"))
                    expect(output).to(contain("Test Succeeded"))
                    expect(output).to(contain("Tests Passed: 0 failed, 1 skipped, 2 total (0.026 seconds)"))
                }
            }

            context("closing footer is identical across all three styles") {
                it("ends every style with byte-for-byte the same 'Test Succeeded'/'Tests Passed' footer") {
                    func run(_ style: RenderStyle) -> String {
                        let engine = Engine(atoms: [], tty: false, style: style)
                        engine.feedLine("Test Case '-[Suite foo]' passed (0.001 seconds).")
                        engine.feedLine(
                            " Executed 1 test, with 0 failures (0 unexpected) in 0.026 (0.030) seconds")
                        return engine.finish()
                    }
                    let expectedFooter =
                        "\nTest Succeeded\nTests Passed: 0 failed, 0 skipped, 1 total (0.026 seconds)\n"
                    expect(run(.classic).hasSuffix(expectedFooter)).to(beTrue())
                    expect(run(.doc).hasSuffix(expectedFooter)).to(beTrue())
                    expect(run(.spec).hasSuffix(expectedFooter)).to(beTrue())
                }
            }
        }
    }
}
