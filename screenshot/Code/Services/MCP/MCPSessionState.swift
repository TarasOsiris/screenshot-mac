#if os(macOS)
import Foundation

/// Groups MCP activity into working sessions. Pure and clock-free — it is handed `now` and returns
/// the events its caller should emit, which is what makes the whole session model unit-testable
/// without PostHog (inert under XCTest) or a sleeping test.
///
/// A session is an idle-gap window rather than a connection or a handshake: the server runs on
/// `StatelessHTTPServerTransport`, and every client re-sends `initialize` (see
/// `MCPServerService.makeStartedServer`), so neither of those is one-per-session.
nonisolated struct MCPSessionState {
    static let idleTimeout: TimeInterval = 10 * 60

    enum Activity: Equatable {
        case handshake
        case toolsListed
        /// `nil` when the client asked for a tool that isn't in our catalog.
        case toolCall(MCPToolName?)

        var analyticsSource: String {
            switch self {
            case .handshake: "handshake"
            case .toolsListed: "list_tools"
            case .toolCall: "tool_call"
            }
        }
    }

    struct Summary: Equatable {
        let id: UUID
        let durationMs: Int
        let toolCallCount: Int
        let distinctToolCount: Int
    }

    /// What the caller must emit, finished first: a lapsed session's summary, then the session
    /// that replaced it.
    struct Outcome: Equatable {
        struct Started: Equatable {
            let id: UUID
            let source: String
        }

        var finished: Summary?
        var started: Started?

        var isEmpty: Bool { finished == nil && started == nil }
    }

    private struct Open {
        let id = UUID()
        let source: String
        let startedAt: Date
        var lastActivityAt: Date
        var toolCallCount = 0
        /// Typed, so a client-supplied tool name can never reach a count that leaves the device.
        var distinctTools: Set<MCPToolName> = []

        init(source: String, startedAt: Date) {
            self.source = source
            self.startedAt = startedAt
            lastActivityAt = startedAt
        }

        var summary: Summary {
            Summary(
                id: id,
                durationMs: Int(lastActivityAt.timeIntervalSince(startedAt) * 1000),
                toolCallCount: toolCallCount,
                distinctToolCount: distinctTools.count
            )
        }
    }

    private var open: Open?

    var currentSessionId: UUID? { open?.id }

    mutating func note(_ activity: Activity, at now: Date) -> (outcome: Outcome, sessionId: UUID) {
        var outcome = Outcome()

        if let current = open, now.timeIntervalSince(current.lastActivityAt) >= Self.idleTimeout {
            outcome.finished = current.summary
            open = nil
        }

        var session: Open
        if let current = open {
            session = current
        } else {
            session = Open(source: activity.analyticsSource, startedAt: now)
            outcome.started = Outcome.Started(id: session.id, source: session.source)
        }

        // Measured from the session's own activity, so a clock that jumps backwards can't produce
        // a negative duration.
        session.lastActivityAt = max(session.lastActivityAt, now)
        if case .toolCall(let tool) = activity {
            session.toolCallCount += 1
            if let tool { session.distinctTools.insert(tool) }
        }

        open = session
        return (outcome, session.id)
    }

    /// Idempotent: a normal quit closes via both the server stop and the termination flush.
    mutating func closed() -> Outcome {
        guard let current = open else { return Outcome() }
        open = nil
        return Outcome(finished: current.summary)
    }
}
#endif
