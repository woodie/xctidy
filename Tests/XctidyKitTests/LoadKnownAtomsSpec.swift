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

/// One QuickSpec class per file, one top-level `describe` per file, matching
/// the file's subject (here, `loadKnownAtoms` from `PathSplitting.swift`).
/// This is the shape new specs in this project -- and in any project using
/// xctidy -- should follow: it's what makes a single file isolatable by
/// class name with `-only-testing:`, no hunting for what to focus. See
/// docs/DEVELOPMENT.md's "Test" section and the README's "Writing specs"
/// section for why.
final class LoadKnownAtomsSpec: QuickSpec {
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
    }
}
