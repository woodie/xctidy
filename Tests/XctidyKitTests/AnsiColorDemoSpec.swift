import Quick
import Nimble
@testable import XctidyKit

/// A *real* Quick spec (not a fixture string) whose second `it`'s bare prose comma ("red, not yellow") only atom-dictionary disambiguation resolves correctly. See docs/COMMENTS.md.
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
