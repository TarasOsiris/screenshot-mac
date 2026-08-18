import Foundation
@testable import Screenshot_Bro
import Testing

/// Preselecting the wrong app is worse than preselecting none — the next screen uploads to
/// whatever is selected — so the threshold behaviour is the part worth pinning.
struct AppStoreConnectAppMatcherTests {

    private func app(_ name: String, id: String = UUID().uuidString) -> ASCApp {
        ASCApp(id: id, attributes: .init(name: name, bundleId: "com.example.\(id)", sku: nil, primaryLocale: nil))
    }

    @Test func matchesExactNameIgnoringCaseAndPunctuation() {
        let apps = [app("Coffee Lib"), app("Screenshot Bro!")]
        let match = AppStoreConnectAppMatcher.closestApp(projectName: "screenshot bro", in: apps)
        #expect(match?.attributes.name == "Screenshot Bro!")
    }

    /// The containment bonus is what makes a suffixed store name win over a closer-by-edit-distance
    /// near-miss. It is only +0.2, so it tips close calls rather than overriding the distance.
    @Test func containmentBonusTipsACloseCall() {
        let apps = [app("Screenshot Bro Kit"), app("Screenshit Brox")]
        let match = AppStoreConnectAppMatcher.closestApp(projectName: "Screenshot Bro", in: apps)
        #expect(match?.attributes.name == "Screenshot Bro Kit")
    }

    /// …and it does not: a much longer name loses on similarity even though it contains the target.
    @Test func containmentDoesNotRescueAMuchLongerName() {
        let apps = [app("Screenshot Bro: The Complete App Store Screenshot Kit")]
        #expect(AppStoreConnectAppMatcher.closestApp(projectName: "Screenshot Bro", in: apps) == nil)
    }

    @Test func returnsNilWhenNothingIsCloseEnough() {
        let apps = [app("Coffee Lib"), app("Table Tennis Tracker")]
        #expect(AppStoreConnectAppMatcher.closestApp(projectName: "Screenshot Bro", in: apps) == nil)
    }

    @Test func returnsNilForAnEmptyOrPunctuationOnlyProjectName() {
        let apps = [app("Screenshot Bro")]
        #expect(AppStoreConnectAppMatcher.closestApp(projectName: "", in: apps) == nil)
        #expect(AppStoreConnectAppMatcher.closestApp(projectName: "— …", in: apps) == nil)
    }

    @Test func returnsNilForAnEmptyAppList() {
        #expect(AppStoreConnectAppMatcher.closestApp(projectName: "Screenshot Bro", in: []) == nil)
    }

    @Test func normalizedNameStripsEverythingButAlphanumerics() {
        #expect(AppStoreConnectAppMatcher.normalizedName("Screenshot Bro: 2.0!") == "screenshotbro20")
    }

    @Test func levenshteinHandlesEmptyAndIdenticalInputs() {
        #expect(AppStoreConnectAppMatcher.levenshtein([], Array("abc")) == 3)
        #expect(AppStoreConnectAppMatcher.levenshtein(Array("abc"), []) == 3)
        #expect(AppStoreConnectAppMatcher.levenshtein(Array("abc"), Array("abc")) == 0)
        #expect(AppStoreConnectAppMatcher.levenshtein(Array("kitten"), Array("sitting")) == 3)
    }
}
