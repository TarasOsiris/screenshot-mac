import Foundation
@testable import Screenshot_Bro
import Testing

// Both settings panes derived this state independently. These pin the precedence, which is the
// part that would be easy to get subtly wrong when there was a copy per store.
struct StoreCredentialsStatusTests {

    /// Demo mode outranks everything — it is what lets App Review run the upload flow with no
    /// credentials at all, so it must win even when credentials exist and a test has passed.
    @Test func demoModeWinsOverEveryOtherSignal() {
        for connected in [true, false] {
            for hasCredentials in [true, false] {
                #expect(
                    StoreCredentialsStatus.resolve(
                        isDemoMode: true,
                        connectionTestPassed: connected,
                        hasCredentials: hasCredentials
                    ) == .demoMode
                )
            }
        }
    }

    @Test func aPassingTestOutranksMerelyHavingCredentials() {
        #expect(
            StoreCredentialsStatus.resolve(isDemoMode: false, connectionTestPassed: true, hasCredentials: true)
                == .connected
        )
        #expect(
            StoreCredentialsStatus.resolve(isDemoMode: false, connectionTestPassed: false, hasCredentials: true)
                == .readyToTest
        )
    }

    @Test func noCredentialsMeansFinishSetup() {
        #expect(
            StoreCredentialsStatus.resolve(isDemoMode: false, connectionTestPassed: false, hasCredentials: false)
                == .finishSetup
        )
    }

    /// A passing test with no credentials shouldn't be reachable, but if it happens the pane must
    /// still report something truthful rather than claiming setup is unfinished.
    @Test func aPassingTestWithoutCredentialsStillReadsAsConnected() {
        #expect(
            StoreCredentialsStatus.resolve(isDemoMode: false, connectionTestPassed: true, hasCredentials: false)
                == .connected
        )
    }

    @Test func everyStateHasADistinctTitleAndSymbol() {
        let titles = StoreCredentialsStatus.allCases.map(\.title)
        let symbols = StoreCredentialsStatus.allCases.map(\.symbolName)
        #expect(Set(titles).count == titles.count)
        #expect(Set(symbols).count == symbols.count)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(symbols.allSatisfy { !$0.isEmpty })
    }
}
