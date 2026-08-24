#if os(macOS)
import Foundation

/// Turns MCP activity into `mcp_session_started` / `mcp_session_finished`, so the funnel has an
/// "an agent actually connected" step and per-tool events can be grouped by working session.
///
/// `nonisolated` + a lock rather than an actor or `@MainActor`: the call sites span three
/// isolation domains — `MCPToolExecutor` (`@MainActor`), the SDK's `@Sendable` method handlers,
/// and `AppState.flushPendingSavesSynchronously`, which is deliberately synchronous and cannot
/// await anything without losing the race with process exit. A lock is callable inline from all
/// three, so a session can never open *after* the tool call that opened it.
nonisolated final class MCPSessionTracker: @unchecked Sendable {
    static let shared = MCPSessionTracker()

    private let lock = NSLock()
    private var state = MCPSessionState()

    var currentSessionId: String? { lock.withLock { state.currentSessionId?.uuidString } }

    /// Returns the id of the session this activity belongs to.
    @discardableResult
    func note(_ activity: MCPSessionState.Activity, at now: Date = Date()) -> String {
        let (outcome, sessionId) = lock.withLock { state.note(activity, at: now) }
        emit(outcome)
        return sessionId.uuidString
    }

    func closeCurrentSession() {
        emit(lock.withLock { state.closed() })
    }

    /// Never call this with the lock held: `capture` is not our code, and anything re-entering the
    /// tracker from it would deadlock.
    private func emit(_ outcome: MCPSessionState.Outcome) {
        if let finished = outcome.finished {
            AnalyticsService.capture(.mcpSessionFinished, [
                .mcpSessionId: finished.id.uuidString,
                .durationMs: finished.durationMs,
                .toolCallCount: finished.toolCallCount,
                .distinctToolCount: finished.distinctToolCount,
            ])
        }
        if let started = outcome.started {
            AnalyticsService.capture(.mcpSessionStarted, [
                .mcpSessionId: started.id.uuidString,
                .source: started.source,
            ])
        }
    }
}
#endif
