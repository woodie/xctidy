import Quick
import Nimble
@testable import XctidyKit

final class EngineSpec: QuickSpec {
    override static func spec() {
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
