import Quick
import Nimble
@testable import XctidyKit

final class VersionFlagSpec: QuickSpec {
    override static func spec() {
        describe("wantsVersion") {
            it("matches the long flag") {
                expect(wantsVersion(["--version"])).to(beTrue())
            }

            it("matches the short flag") {
                expect(wantsVersion(["-v"])).to(beTrue())
            }

            it("matches regardless of position among other args") {
                expect(wantsVersion(["-fd", "--version", "Tests"])).to(beTrue())
                expect(wantsVersion(["Tests", "-v"])).to(beTrue())
            }

            it("does not match other flags or positionals") {
                expect(wantsVersion(["-fd", "Tests"])).to(beFalse())
                expect(wantsVersion(["--format", "spec"])).to(beFalse())
            }

            it("does not match on an empty argument list") {
                expect(wantsVersion([])).to(beFalse())
            }
        }
    }
}
