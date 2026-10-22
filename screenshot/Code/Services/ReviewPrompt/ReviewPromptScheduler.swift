import Foundation

/// The one path from a success moment (export or store upload) to the system review prompt.
@MainActor
final class ReviewPromptScheduler {
    enum Trigger: String {
        case export
        case upload
    }

    /// A due ask still blocked after this long no longer follows from the success that earned it.
    static let pendingLifetime: TimeInterval = 10 * 60

    /// Injected: it is a SwiftUI environment value, and tests observe it without one.
    var requestReview: () -> Void = {}
    /// No export, alert, sheet, wizard or paywall up, and the app frontmost.
    var isClearToAsk: () -> Bool = { true }

    private let policy: ReviewPromptPolicy
    private let delay: TimeInterval
    private var pending: (trigger: Trigger, since: Date)?
    private var attemptTask: Task<Void, Never>?

    /// `delay` lets the success feedback (toolbar "Exported", the Finder reveal, a sheet closing) land first.
    init(policy: ReviewPromptPolicy, delay: TimeInterval = 2.5) {
        self.policy = policy
        self.delay = delay
    }

    var hasPendingAsk: Bool { pending != nil }

    func recordSuccess(_ trigger: Trigger) {
        // The system sheet has no listing to send a review to outside the App Store.
        guard !DistributionChannel.isDirect else { return }
        policy.recordSuccess()
        guard policy.isPromptDue else { return }
        pending = (trigger, policy.now())
        scheduleAttempt()
    }

    /// Retries a blocked ask — call when whatever blocked it goes away.
    func resume() {
        guard pending != nil else { return }
        scheduleAttempt()
    }

    func cancel() {
        attemptTask?.cancel()
        attemptTask = nil
        pending = nil
    }

    /// Drops the closures, which capture the owning view, and blocks asking so a late success only counts.
    func tearDown() {
        cancel()
        requestReview = {}
        isClearToAsk = { false }
    }

    private func scheduleAttempt() {
        attemptTask?.cancel()
        attemptTask = .delayed(delay) { [weak self] in self?.attempt() }
    }

    /// A blocked ask waits for `resume()`; only one that reaches the screen spends the policy's turn.
    private func attempt() {
        attemptTask = nil
        guard let pending else { return }
        guard policy.now().timeIntervalSince(pending.since) < Self.pendingLifetime, policy.isPromptDue else {
            cancel()
            return
        }
        guard isClearToAsk() else { return }
        self.pending = nil
        policy.markPrompted()
        AnalyticsService.capture(.reviewPromptRequested, [.trigger: pending.trigger.rawValue, .count: policy.successCount])
        requestReview()
    }
}
