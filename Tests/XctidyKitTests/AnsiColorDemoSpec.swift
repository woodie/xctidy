import Quick
import Nimble
@testable import XctidyKit

/// A *real* Quick spec -- not a hand-built fixture string -- so `swift test`
/// emits a genuine comma-flattened XCTest name, the same kind any
/// Quick/Nimble project produces. Pipe it through to see the tree:
///
///   swift test 2>&1 | .build/release/xctidy Tests/XctidyKitTests
///
/// The second `it` below has a bare prose comma ("red, not yellow") that
/// sits *outside* any parentheses. The paren-depth heuristic alone would
/// mis-split that into a 4th tree level. Only the atom-dictionary
/// disambiguation -- cross-referencing this file's own describe/context/it
/// literals -- resolves it correctly, which is the actual point of this demo.
final class AnsiColorDemoSpec: QuickSpec {
    override static func spec() {
        describe("AnsiColor") {
            context("when rendering a test label") {
                it("renders a passed label in green (32)") {
                    expect(AnsiColor.green.rawValue).to(equal("32"))
                }

                it("renders a failed label in red, not yellow (easy to confuse under stage lighting)") {
                    expect(AnsiColor.red.rawValue).to(equal("31"))
                }
            }
        }
    }
}
