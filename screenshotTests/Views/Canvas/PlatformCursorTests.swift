@testable import Screenshot_Bro
import Testing

/// Two slots with owners, not a stack. Each case here is a way the stack version got stuck.
@MainActor
@Suite(.serialized)
struct PlatformCursorTests {
    init() { PlatformCursor.resetForTesting() }

    /// The bug the whole type exists for: a drag carries the pointer off its handle, SwiftUI
    /// fires the hover-exit, and the cursor used to revert mid-gesture.
    @Test func aHeldCursorSurvivesItsOwnHoverExit() {
        PlatformCursor.hover(.resize(edge: .bottomRight, rotation: 0), for: .resizeHandle(.bottomRight))
        PlatformCursor.hold(.resize(edge: .bottomRight, rotation: 0), for: .resizeHandle(.bottomRight))

        PlatformCursor.hover(nil, for: .resizeHandle(.bottomRight))
        #expect(PlatformCursor.resolvedKind == .resize(edge: .bottomRight, rotation: 0))

        PlatformCursor.release(.resizeHandle(.bottomRight))
        #expect(PlatformCursor.resolvedKind == .arrow)
    }

    /// Releasing hands the cursor back to whatever the pointer is still over, rather than
    /// hard-coding the arrow the way `setArrow()` did.
    @Test func releaseFallsBackToTheHover() {
        PlatformCursor.hover(.resize(edge: .top, rotation: 0), for: .resizeHandle(.top))
        PlatformCursor.hold(.closedHand, for: .shapeBody)
        PlatformCursor.release(.shapeBody)
        #expect(PlatformCursor.resolvedKind == .resize(edge: .top, rotation: 0))
    }

    /// A handle's hit area straddles the shape's edge, so the row's hover fires while the pointer
    /// is still on the knob. The layer that paints on top names the cursor.
    @Test func theCanvasHoverCannotOutrankAHandle() {
        PlatformCursor.hover(.resize(edge: .topLeft, rotation: 0), for: .resizeHandle(.topLeft))
        PlatformCursor.hover(.openHand, for: .canvas)
        #expect(PlatformCursor.resolvedKind == .resize(edge: .topLeft, rotation: 0))

        // Leaving the handle hands the slot over — the canvas isn't blocked, just outranked.
        PlatformCursor.hover(nil, for: .resizeHandle(.topLeft))
        PlatformCursor.hover(.openHand, for: .canvas)
        #expect(PlatformCursor.resolvedKind == .openHand)
    }

    /// A stale exit from a handle the pointer has already left must not clear the one it entered.
    @Test func anOtherOwnersClearIsIgnored() {
        PlatformCursor.hover(.resize(edge: .right, rotation: 0), for: .resizeHandle(.right))
        PlatformCursor.hover(nil, for: .resizeHandle(.left))
        #expect(PlatformCursor.resolvedKind == .resize(edge: .right, rotation: 0))
    }

    /// `MiddleMousePanView.install()` calls `uninstall()` first, which releases — it must not drop
    /// a hold taken by an in-flight canvas drag. This is the guard `didPushCursor` used to give.
    @Test func releaseOnlyDropsItsOwnHold() {
        PlatformCursor.hold(.closedHand, for: .shapeBody)
        PlatformCursor.release(.pan)
        #expect(PlatformCursor.resolvedKind == .closedHand)

        PlatformCursor.release(.shapeBody)
        #expect(PlatformCursor.resolvedKind == .arrow)
    }

    /// A handle torn down mid-gesture gets neither hover-exit nor gesture-end callbacks.
    @Test func teardownClearsTheHoverAndHoldClaims() {
        PlatformCursor.hover(.resize(edge: .topLeft, rotation: 0), for: .resizeHandle(.topLeft))
        PlatformCursor.hold(.resize(edge: .topLeft, rotation: 0), for: .resizeHandle(.topLeft))
        // What `.onDisappear` does.
        PlatformCursor.clear(.resizeHandle(.topLeft))

        PlatformCursor.hold(.closedHand, for: .shapeBody)
        PlatformCursor.release(.shapeBody)
        #expect(PlatformCursor.resolvedKind == .arrow)
    }
}
