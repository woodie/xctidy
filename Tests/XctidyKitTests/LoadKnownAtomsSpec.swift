import Quick
import Nimble
import Foundation
@testable import XctidyKit

// MARK: - Fixtures

// Real chains from next-caltrain-swift's Tests/, proving both disambiguation edge cases: a parenthetical aside and a bare prose comma with no parens. See docs/COMMENTS.md.
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

            it("recurses into per-target subdirectories like Tests/<ModuleName>Tests/") {
                // Regression test for the non-recursive-glob bug: SwiftPM nests specs one level under Tests/, e.g. Tests/FooKitTests/; see docs/COMMENTS.md (loadKnownAtoms).
                let dir = writeTempSpecsDir([:])
                let subdir = (dir as NSString).appendingPathComponent("FooKitTests")
                try! FileManager.default.createDirectory(
                    atPath: subdir, withIntermediateDirectories: true)
                try! caltrainServiceSwift.write(
                    toFile: (subdir as NSString).appendingPathComponent("CaltrainServiceSpec.swift"),
                    atomically: true, encoding: .utf8)

                let atoms = loadKnownAtoms(specsDir: dir)

                expect(atoms).to(contain("CaltrainService"))
                expect(atoms).to(contain("is not a transfer, since both endpoints are South County"))
            }
        }
    }
}
