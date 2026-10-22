import Foundation
@testable import Screenshot_Bro
import Testing

/// A clock a test can move while a scheduler holds on to it.
@MainActor
final class ReviewPromptTestClock {
    var now = Date(timeIntervalSinceReferenceDate: 30 * 86400)
}

/// One success away from a due prompt, with no delay and a counter in place of the system prompt.
@MainActor
func makePrimedReviewPrompt(
    defaults: UserDefaults,
    clock: ReviewPromptTestClock = ReviewPromptTestClock(),
    delay: TimeInterval = 0
) -> (scheduler: ReviewPromptScheduler, policy: ReviewPromptPolicy, requests: () -> Int) {
    let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.0") { clock.now }
    defaults.set(2, forKey: ReviewPromptPolicy.Key.successCount)
    defaults.set(clock.now.timeIntervalSinceReferenceDate - 15 * 86400, forKey: ReviewPromptPolicy.Key.firstSuccessDate)
    let scheduler = ReviewPromptScheduler(policy: policy, delay: delay)
    var requests = 0
    scheduler.requestReview = { requests += 1 }
    return (scheduler, policy, { requests })
}

/// Lets a zero-delay attempt run, then a little longer so a wrongly-fired one would be seen.
@MainActor
func settleReviewPrompt(requests: () -> Int, expecting expected: Int) async throws {
    for _ in 0..<40 where requests() < expected {
        try await Task.sleep(for: .milliseconds(25))
    }
    try await Task.sleep(for: .milliseconds(50))
}

@MainActor
struct ReviewPromptSchedulerTests {

    @Test func aDueSuccessAsksOnceAndSpendsTheTurn() async throws {
        let primed = makePrimedReviewPrompt(defaults: makeIsolatedDefaults("due"))

        primed.scheduler.recordSuccess(.upload)
        try await settleReviewPrompt(requests: primed.requests, expecting: 1)

        #expect(primed.requests() == 1)
        #expect(primed.policy.successCount == 3)
        #expect(!primed.policy.isPromptDue, "the ask that reached the screen spends this version's turn")
        #expect(!primed.scheduler.hasPendingAsk)
    }

    /// An ask that lands on a sheet, an alert or a backgrounded app is one nobody sees.
    @Test func aBlockedAskWaitsAndSpendsNothingUntilItIsShown() async throws {
        let primed = makePrimedReviewPrompt(defaults: makeIsolatedDefaults("blocked"))
        var isClear = false
        primed.scheduler.isClearToAsk = { isClear }

        primed.scheduler.recordSuccess(.export)
        try await settleReviewPrompt(requests: primed.requests, expecting: 0)

        #expect(primed.requests() == 0)
        #expect(primed.policy.isPromptDue, "a blocked ask must not spend the turn")
        #expect(primed.scheduler.hasPendingAsk)

        isClear = true
        primed.scheduler.resume()
        try await settleReviewPrompt(requests: primed.requests, expecting: 1)

        #expect(primed.requests() == 1)
        #expect(!primed.policy.isPromptDue)
    }

    @Test func aStaleAskIsDropped() async throws {
        let clock = ReviewPromptTestClock()
        let primed = makePrimedReviewPrompt(defaults: makeIsolatedDefaults("stale"), clock: clock)
        var isClear = false
        primed.scheduler.isClearToAsk = { isClear }

        primed.scheduler.recordSuccess(.export)
        try await settleReviewPrompt(requests: primed.requests, expecting: 0)
        clock.now = clock.now.addingTimeInterval(ReviewPromptScheduler.pendingLifetime + 1)
        isClear = true
        primed.scheduler.resume()
        try await settleReviewPrompt(requests: primed.requests, expecting: 0)

        #expect(primed.requests() == 0)
        #expect(!primed.scheduler.hasPendingAsk)
        #expect(primed.policy.isPromptDue, "dropping the ask leaves the turn for the next success")
    }

    @Test func aSuccessBeforeTheThresholdOnlyCounts() async throws {
        let defaults = makeIsolatedDefaults("early")
        let policy = ReviewPromptPolicy(defaults: defaults, currentVersion: "1.0") { Date() }
        let scheduler = ReviewPromptScheduler(policy: policy, delay: 0)
        var requests = 0
        scheduler.requestReview = { requests += 1 }

        scheduler.recordSuccess(.export)
        try await settleReviewPrompt(requests: { requests }, expecting: 0)

        #expect(requests == 0)
        #expect(policy.successCount == 1)
        #expect(!scheduler.hasPendingAsk)
    }
}
