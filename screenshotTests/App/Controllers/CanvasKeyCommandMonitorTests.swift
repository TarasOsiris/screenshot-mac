import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
@Suite(.serialized)
struct CanvasKeyCommandMonitorTests {

    /// The monitor is owned by AppState and holds the handler closures. If those captured AppState
    /// strongly the cycle would be unbreakable: every AppState in this suite would leak *and*
    /// leave a live local NSEvent monitor installed, still firing against a state the test
    /// believes is gone. Nothing else in the suite would notice.
    @Test func appStateDeallocatesDespiteOwningTheKeyMonitor() {
        weak var weakState: AppState?
        let tempDir: URL

        do {
            let (state, dir) = makeEmptyTestState()
            tempDir = dir
            weakState = state
            #expect(weakState != nil)
        }

        #expect(weakState == nil, "AppState leaked — check that every key-command handler captures self weakly")
        cleanupTestState(tempDir)
    }

    /// The handlers are what an installed monitor would call. This exercises the same closures
    /// AppState builds, without needing a real key event.
    @Test func handlersReachTheirTargetWeakly() {
        final class Target { var nudges: [(CGFloat, CGFloat)] = []; var deletes = 0 }
        weak var weakTarget: Target?
        var handlers: CanvasKeyCommandMonitor.Handlers?

        do {
            let target = Target()
            weakTarget = target
            handlers = .init(
                hasSelection: { true },
                isEditingText: { false },
                nudge: { [weak target] dx, dy in target?.nudges.append((dx, dy)) },
                delete: { [weak target] in target?.deletes += 1 }
            )
            handlers?.nudge(-1, 0)
            handlers?.delete()
            #expect(target.nudges.count == 1)
            #expect(target.deletes == 1)
        }

        #expect(weakTarget == nil, "the handlers must not keep their target alive")
        // Calling into a released target is a no-op rather than a crash.
        handlers?.nudge(1, 0)
        handlers?.delete()
    }
}
