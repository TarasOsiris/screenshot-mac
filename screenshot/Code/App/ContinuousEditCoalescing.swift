import Foundation

/// Coalesces a burst of rapid edits (slider drags, key-repeat nudges, keystrokes) into a single
/// undo step. The finish action — which registers that one undo step from a base captured at the
/// start of the burst — is supplied on the first edit and runs exactly once, when the burst
/// settles (debounced) or is force-committed at an undo-stack boundary.
///
/// `AppState` keeps one of these per debounced interaction in a registry, so "is anything
/// pending?", cancellation, and commit-all iterate the registry instead of enumerating a
/// per-subsystem field cluster by hand (which previously had to be kept in sync in three places).
@MainActor
final class DebouncedUndoCoalescer {
    let debounceDelay: TimeInterval
    private var finishTask: DispatchWorkItem?
    private var commit: (() -> Void)?
    /// Identity of the burst in progress (a shape or row id), so a differently-targeted edit can
    /// finish the previous burst first, and views can read the in-flight target. Nil when idle.
    private(set) var activeId: UUID?

    init(debounceDelay: TimeInterval) { self.debounceDelay = debounceDelay }

    /// True while a burst is captured but not yet registered as an undo step.
    var isActive: Bool { commit != nil }

    /// Start a burst if none is active — `makeCommit` runs once, capturing the base and returning
    /// the finish action — recording `id` as the active target. Call `arm()` after applying each
    /// edit to (re)start the debounce timer.
    func begin(id: UUID?, makeCommit: () -> (() -> Void)) {
        if commit == nil { commit = makeCommit() }
        activeId = id
    }

    /// (Re)arm the debounce timer. No-op when idle.
    func arm() {
        guard commit != nil else { return }
        finishTask?.cancel()
        let task = DispatchWorkItem { [weak self] in self?.finish() }
        finishTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceDelay, execute: task)
    }

    /// Commit the burst as a single undo step now. No-op when idle. The commit closure is cleared
    /// before it runs, so a re-entrant `finish()` can't register the step twice. `activeId` stays
    /// set until *after* commit, because the commit closure may need it (e.g. to locate the row
    /// whose throttled value it flushes) — it is cleared once commit returns.
    func finish() {
        finishTask?.cancel()
        finishTask = nil
        guard let commit else { return }
        self.commit = nil
        commit()
        activeId = nil
    }

    /// Drop the burst without registering an undo step (project switch / reset).
    func cancel() {
        finishTask?.cancel()
        finishTask = nil
        commit = nil
        activeId = nil
    }
}

/// Throttles the *application* of a continuous edit to ~30fps: the model is written at most once
/// per `interval`, with the latest value flushed when the interval elapses. This keeps expensive
/// re-renders off every slider/drag tick while never dropping the final value.
///
/// The apply action is set once (in `AppState.init`, where `self` is available) rather than at
/// construction, so the throttle can be a stored `let`.
@MainActor
final class ContinuousApplyThrottle<Payload> {
    let interval: CFAbsoluteTime
    /// Writes `Payload` into the document. Set once after construction.
    var apply: ((Payload) -> Void)?
    private(set) var lastApply: CFAbsoluteTime = 0
    private var flushTask: DispatchWorkItem?
    private var pending: Payload?

    init(interval: CFAbsoluteTime) { self.interval = interval }

    /// The latest value awaiting a throttled flush, or nil once applied.
    var pendingValue: Payload? { pending }
    var hasPending: Bool { pending != nil }

    /// Apply `value` now if the interval has elapsed since the last apply, otherwise stash it as
    /// the pending value and schedule a flush for the remainder of the interval.
    func submit(_ value: Payload) {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastApply >= interval {
            apply?(value)
            pending = nil
            lastApply = now
            flushTask?.cancel()
            flushTask = nil
        } else {
            pending = value
            if flushTask == nil {
                let task = DispatchWorkItem { [weak self] in self?.flush() }
                flushTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + (interval - (now - lastApply)), execute: task)
            }
        }
    }

    /// Apply the pending value immediately, if any.
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard let value = pending else { return }
        apply?(value)
        pending = nil
        lastApply = CFAbsoluteTimeGetCurrent()
    }

    /// Clear all timing/pending state (end of burst or reset).
    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        lastApply = 0
    }

    /// Test seam: treat the last apply as just-now so the next `submit` coalesces instead of
    /// applying immediately.
    func markRecentApply() { lastApply = CFAbsoluteTimeGetCurrent() }
}
