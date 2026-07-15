import Quick
import Nimble
@testable import XctidyKit

final class SplitPathSpec: QuickSpec {
    override static func spec() {
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
                    // Deliberately ambiguous: two valid decompositions exist for this atom set, so splitPath must fall back to the heuristic.
                    let atoms: Set<String> = ["a", "b, c", "a, b", "c"]
                    let path = splitPath("a, b, c", atoms: atoms)
                    expect(path).to(equal(["a", "b", "c"]))  // heuristic: plain top-level split
                }
            }
        }
    }
}
