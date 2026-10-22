import Foundation
@testable import Screenshot_Bro
import Testing

/// These four rules shipped for a long time with no coverage at all, because they lived in a
/// `ContentView` extension backed by `@AppStorage`.
@MainActor
struct ReviewPromptPolicyTests {

    private let day: TimeInterval = 86400

    private func policy(
        _ defaults: UserDefaults,
        version: String = "1.0",
        now: @escaping () -> Date
    ) -> ReviewPromptPolicy {
        ReviewPromptPolicy(defaults: defaults, currentVersion: version, now: now)
    }

    /// One success moment, then the check — and the prompt, when the check passes, the way
    /// `ReviewPromptScheduler` spends it.
    private func succeed(_ p: ReviewPromptPolicy) -> Bool {
        p.recordSuccess()
        guard p.isPromptDue else { return false }
        p.markPrompted()
        return true
    }

    @Test func doesNotPromptBeforeThreeSuccesses() {
        let defaults = makeIsolatedDefaults("count")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        #expect(succeed(p) == false)
        now = start.addingTimeInterval(20 * day)
        #expect(succeed(p) == false, "second success, still under the minimum")
    }

    @Test func doesNotPromptWithinTwoWeeksOfTheFirstSuccess() {
        let defaults = makeIsolatedDefaults("young")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        for offset in [0.0, 1.0, 13.0] {
            now = start.addingTimeInterval(offset * day)
            #expect(succeed(p) == false)
        }
    }

    @Test func promptsAfterThreeSuccessesAndTwoWeeks() {
        let defaults = makeIsolatedDefaults("ready")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        #expect(succeed(p) == false)
        now = start.addingTimeInterval(15 * day)
        #expect(succeed(p) == false, "only the second success")
        #expect(succeed(p) == true, "third success, past the 14-day window")
    }

    @Test func promptsAtMostOncePerVersion() {
        let defaults = makeIsolatedDefaults("version")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        _ = succeed(p)
        now = start.addingTimeInterval(15 * day)
        _ = succeed(p)
        #expect(succeed(p) == true)

        now = start.addingTimeInterval(400 * day)
        #expect(succeed(p) == false, "same version, already prompted")

        // A new version reopens the door, but the 120-day gap still applies. The prompt landed on
        // day 15, so day 100 is 85 days later — too soon — and day 200 is 185 days later.
        let tooSoon = policy(defaults, version: "1.1") { start.addingTimeInterval(100 * day) }
        #expect(succeed(tooSoon) == false, "only 85 days since the last prompt")

        let farEnough = policy(defaults, version: "1.1") { start.addingTimeInterval(200 * day) }
        #expect(succeed(farEnough) == true, "new version, past the 120-day gap")
    }

    /// The check is what a delayed ask re-runs at fire time; if it spent the turn, an ask that
    /// never reached the screen would retire the whole version.
    @Test func checkingDoesNotSpendThePrompt() {
        let defaults = makeIsolatedDefaults("pure")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }

        p.recordSuccess()
        now = start.addingTimeInterval(15 * day)
        p.recordSuccess()
        p.recordSuccess()

        #expect(p.isPromptDue)
        #expect(p.isPromptDue, "a second check must see the same answer")
        p.markPrompted()
        #expect(!p.isPromptDue)
    }

    /// An unset version (which is what `Bundle.main.shortVersion` returns under test) would
    /// otherwise match the empty stored value and prompt on the very first success.
    @Test func neverPromptsWithoutAVersion() {
        let defaults = makeIsolatedDefaults("noversion")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let p = policy(defaults, version: "") { start.addingTimeInterval(400 * day) }

        for _ in 0..<5 {
            #expect(succeed(p) == false)
        }
    }

    @Test func resetForgetsEverything() {
        let defaults = makeIsolatedDefaults("reset")
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var now = start
        let p = policy(defaults) { now }
        _ = succeed(p)
        now = start.addingTimeInterval(15 * day)
        _ = succeed(p)
        #expect(succeed(p) == true)

        p.reset()

        #expect(p.successCount == 0)
        for key in [ReviewPromptPolicy.Key.lastPromptedVersion, ReviewPromptPolicy.Key.firstSuccessDate,
                    ReviewPromptPolicy.Key.lastPromptDate] {
            #expect(defaults.object(forKey: key) == nil)
        }
    }
}
