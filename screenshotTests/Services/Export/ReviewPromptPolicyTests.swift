import Foundation
@testable import Screenshot_Bro
import Testing

/// These four rules shipped for a long time with no coverage at all, because they lived in a
/// `ContentView` extension backed by `@AppStorage`.
@MainActor
struct ReviewPromptPolicyTests {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "ReviewPromptPolicyTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private let day: TimeInterval = 86400

    private func policy(
        _ defaults: UserDefaults,
        version: String = "1.0",
        now: @escaping () -> Date
    ) -> ReviewPromptPolicy {
        ReviewPromptPolicy(defaults: defaults, currentVersion: version, now: now)
    }

    @Test func doesNotPromptBeforeThreeExports() {
        let defaults = makeDefaults("count")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        #expect(p.recordExportAndCheck() == false)
        now = start.addingTimeInterval(20 * day)
        #expect(p.recordExportAndCheck() == false, "second export, still under the minimum")
    }

    @Test func doesNotPromptWithinTwoWeeksOfTheFirstExport() {
        let defaults = makeDefaults("young")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        for offset in [0.0, 1.0, 13.0] {
            now = start.addingTimeInterval(offset * day)
            #expect(p.recordExportAndCheck() == false)
        }
    }

    @Test func promptsAfterThreeExportsAndTwoWeeks() {
        let defaults = makeDefaults("ready")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        #expect(p.recordExportAndCheck() == false)
        now = start.addingTimeInterval(15 * day)
        #expect(p.recordExportAndCheck() == false, "only the second export")
        #expect(p.recordExportAndCheck() == true, "third export, past the 14-day window")
    }

    @Test func promptsAtMostOncePerVersion() {
        let defaults = makeDefaults("version")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        _ = p.recordExportAndCheck()
        now = start.addingTimeInterval(15 * day)
        _ = p.recordExportAndCheck()
        #expect(p.recordExportAndCheck() == true)

        now = start.addingTimeInterval(400 * day)
        #expect(p.recordExportAndCheck() == false, "same version, already prompted")

        // A new version reopens the door, but the 120-day gap still applies. The prompt landed on
        // day 15, so day 100 is 85 days later — too soon — and day 200 is 185 days later.
        let tooSoon = policy(defaults, version: "1.1") { start.addingTimeInterval(100 * day) }
        #expect(tooSoon.recordExportAndCheck() == false, "only 85 days since the last prompt")

        let farEnough = policy(defaults, version: "1.1") { start.addingTimeInterval(200 * day) }
        #expect(farEnough.recordExportAndCheck() == true, "new version, past the 120-day gap")
    }

    /// An unset version (which is what `Bundle.main.shortVersion` returns under test) would
    /// otherwise match the empty stored value and prompt on the very first export.
    @Test func neverPromptsWithoutAVersion() {
        let defaults = makeDefaults("noversion")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let p = policy(defaults, version: "") { start.addingTimeInterval(400 * day) }

        for _ in 0..<5 {
            #expect(p.recordExportAndCheck() == false)
        }
    }
}
