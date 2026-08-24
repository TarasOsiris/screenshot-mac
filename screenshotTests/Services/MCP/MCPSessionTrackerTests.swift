import Foundation
@testable import Screenshot_Bro
import Testing

/// Drives the pure core with explicit `Date`s — no sleeping, no shared state, and no dependence on
/// analytics being inert under XCTest.
struct MCPSessionTrackerTests {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Session boundaries

    @Test func firstActivityOpensExactlyOneSession() {
        var state = MCPSessionState()
        let (outcome, _) = state.note(.handshake, at: start)
        #expect(outcome.started != nil)
        #expect(outcome.finished == nil)
        #expect(outcome.started?.source == "handshake")
    }

    @Test func activityWithinTheWindowStaysInTheSameSession() {
        var state = MCPSessionState()
        let (_, first) = state.note(.toolCall(.getProject), at: start)
        let (outcome, second) = state.note(.toolCall(.addRow), at: start.addingTimeInterval(60))
        #expect(first == second)
        #expect(outcome.isEmpty)
    }

    /// Pin both sides of the boundary: the gap test is `>=`, so exactly the timeout closes.
    @Test func idleGapBoundaryIsInclusive() {
        var continuing = MCPSessionState()
        let (_, first) = continuing.note(.toolCall(.getProject), at: start)
        let (justUnder, sameSession) = continuing.note(
            .toolCall(.getProject),
            at: start.addingTimeInterval(MCPSessionState.idleTimeout - 1)
        )
        #expect(justUnder.isEmpty)
        #expect(sameSession == first)

        var lapsing = MCPSessionState()
        let (_, original) = lapsing.note(.toolCall(.getProject), at: start)
        let (atTimeout, replacement) = lapsing.note(
            .toolCall(.getProject),
            at: start.addingTimeInterval(MCPSessionState.idleTimeout)
        )
        #expect(atTimeout.finished?.id == original)
        #expect(atTimeout.started != nil)
        #expect(replacement != original)
    }

    /// The reason the lazy close needs no timer: duration is the session's own span, so noticing
    /// the gap late doesn't inflate it.
    @Test func durationMeasuresLastActivityNotWhenTheGapWasNoticed() {
        var state = MCPSessionState()
        _ = state.note(.toolCall(.getProject), at: start)
        _ = state.note(.toolCall(.addRow), at: start.addingTimeInterval(120))
        let (outcome, _) = state.note(.toolCall(.addRow), at: start.addingTimeInterval(900))
        #expect(outcome.finished?.durationMs == 120_000)
    }

    @Test func reopenedSessionTakesItsOwnSource() {
        var state = MCPSessionState()
        _ = state.note(.handshake, at: start)
        let (outcome, _) = state.note(
            .toolCall(.getProject),
            at: start.addingTimeInterval(MCPSessionState.idleTimeout)
        )
        #expect(outcome.started?.source == "tool_call")
    }

    @Test func clockJumpingBackwardsCannotProduceNegativeDuration() {
        var state = MCPSessionState()
        _ = state.note(.toolCall(.getProject), at: start)
        _ = state.note(.toolCall(.addRow), at: start.addingTimeInterval(-500))
        let outcome = state.closed()
        #expect(outcome.finished?.durationMs == 0)
    }

    // MARK: - Counting

    @Test func countsEveryCallButDedupesDistinctTools() {
        var state = MCPSessionState()
        for tool in [MCPToolName.getProject, .addRow, .getProject, .addShape, .addRow] {
            _ = state.note(.toolCall(tool), at: start)
        }
        let outcome = state.closed()
        #expect(outcome.finished?.toolCallCount == 5)
        #expect(outcome.finished?.distinctToolCount == 3)
    }

    /// An unrecognised name is still a call, but must never reach the distinct set — that set is
    /// typed precisely so a client-supplied string cannot be counted, let alone sent.
    @Test func unknownToolCountsAsACallButNotAsADistinctTool() {
        var state = MCPSessionState()
        _ = state.note(.toolCall(nil), at: start)
        let outcome = state.closed()
        #expect(outcome.finished?.toolCallCount == 1)
        #expect(outcome.finished?.distinctToolCount == 0)
    }

    /// The "connected but never worked" case the funnel reads as the step-3-to-4 drop-off.
    @Test func discoveryOnlySessionFinishesWithNoToolCalls() {
        var state = MCPSessionState()
        _ = state.note(.handshake, at: start)
        _ = state.note(.toolsListed, at: start.addingTimeInterval(1))
        let outcome = state.closed()
        #expect(outcome.finished?.toolCallCount == 0)
        #expect(outcome.finished?.distinctToolCount == 0)
    }

    // MARK: - Closing

    @Test func closingIsIdempotent() {
        var state = MCPSessionState()
        _ = state.note(.handshake, at: start)
        #expect(state.closed().finished != nil)
        // A normal quit closes twice — once when the server stops, once in the termination flush.
        #expect(state.closed().isEmpty)
    }

    @Test func sessionIdsAreUniqueAcrossSessions() {
        var state = MCPSessionState()
        let (_, first) = state.note(.handshake, at: start)
        let (_, second) = state.note(
            .handshake,
            at: start.addingTimeInterval(MCPSessionState.idleTimeout * 2)
        )
        #expect(first != second)
    }
}
