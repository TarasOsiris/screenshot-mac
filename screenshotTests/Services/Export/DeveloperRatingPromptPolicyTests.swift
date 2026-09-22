import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct DeveloperRatingPromptPolicyTests {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "DeveloperRatingPromptPolicyTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func doesNotShowBeforeTwoExports() {
        let defaults = makeDefaults("count")
        let p = DeveloperRatingPromptPolicy(defaults: defaults)

        #expect(p.recordExportAndCheck() == false, "first export")
    }

    @Test func showsOnTheSecondExport() {
        let defaults = makeDefaults("ready")
        let p = DeveloperRatingPromptPolicy(defaults: defaults)

        #expect(p.recordExportAndCheck() == false, "first export")
        #expect(p.recordExportAndCheck() == true, "second export")
    }

    /// The sheet is presented on a delay, so the check cannot be what retires the ask: a window
    /// closed inside that delay has to leave it for the next export.
    @Test func checkAloneDoesNotSpendTheAsk() {
        let defaults = makeDefaults("unspent")
        let p = DeveloperRatingPromptPolicy(defaults: defaults)

        _ = p.recordExportAndCheck()
        #expect(p.recordExportAndCheck() == true, "second export")
        #expect(p.recordExportAndCheck() == true, "third export, ask never shown")
    }

    @Test func showsOnlyOnceEver() {
        let defaults = makeDefaults("once")
        let p = DeveloperRatingPromptPolicy(defaults: defaults)

        _ = p.recordExportAndCheck()
        #expect(p.recordExportAndCheck() == true, "second export")
        p.markShown()

        for _ in 0..<5 {
            #expect(p.recordExportAndCheck() == false, "already shown")
        }
    }

    /// Two exports inside the presentation delay schedule two sheets; only the first may count.
    @Test func markShownReportsOnlyTheCallThatSpentIt() {
        let defaults = makeDefaults("idempotent")
        let p = DeveloperRatingPromptPolicy(defaults: defaults)

        #expect(p.markShown() == true)
        #expect(p.markShown() == false)
    }

    /// A fresh `DeveloperRatingPromptPolicy` instance reads the same `UserDefaults` state as a
    /// prior one — the model recreates this on every launch, so persistence must not depend on
    /// keeping one instance alive.
    @Test func persistsAcrossInstances() {
        let defaults = makeDefaults("instances")

        _ = DeveloperRatingPromptPolicy(defaults: defaults).recordExportAndCheck()
        #expect(DeveloperRatingPromptPolicy(defaults: defaults).recordExportAndCheck() == true)
        DeveloperRatingPromptPolicy(defaults: defaults).markShown()
        #expect(DeveloperRatingPromptPolicy(defaults: defaults).recordExportAndCheck() == false)
    }
}
