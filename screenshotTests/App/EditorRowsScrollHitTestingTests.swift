#if os(macOS)
import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// A leaf with a real `NSView` behind it. `Color` has none — `hitTest` returns the hosting view for
/// it either way — so it cannot say whether the gate did anything.
private struct HitProbe: NSViewRepresentable {
    final class ProbeView: NSView {}

    func makeNSView(context: Context) -> NSView { ProbeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// One row of the mirror: the fixed-height `Color.clear` shell, a header-sized block, and the row's
/// own horizontal `ScrollView` over content wider than the viewport.
private struct MirrorRow<Canvas: View>: View {
    @ViewBuilder let canvas: Canvas

    var body: some View {
        Color.clear
            .frame(height: 240)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 30)
                    ScrollView(.horizontal) { canvas }
                }
            }
    }
}

/// The editor's shape after the fix: the gate sits *inside* each row's horizontal scroll view, so
/// the scroll view itself stays in the hit-test tree.
private struct GateInsideRowHost: View {
    let scrollState: EditorScrollState

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    MirrorRow {
                        HitProbe()
                            .frame(width: 4_000, height: 200)
                            .inertWhileEditorScrolls()
                    }
                }
            }
            .environment(scrollState)
        }
    }
}

/// The shape `57c6e467` shipped: the gate wraps the whole list, so it takes every nested horizontal
/// scroll view with it.
private struct GateAroundListHost: View {
    let scrollState: EditorScrollState

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(0..<3) { _ in
                    MirrorRow { Color.red.frame(width: 4_000, height: 200) }
                }
            }
            .allowsHitTesting(!scrollState.isScrolling)
            .environment(scrollState)
        }
    }
}

/// Trackpad horizontal scrolling of a row canvas broke because the editor's row list dropped hit
/// testing for the whole `LazyVStack` while it moved — see `inertWhileEditorScrolls()`.
///
/// These pin hit *routing*, not that a wheel event scrolls: synthesizing one depends on
/// `NSScrollView`'s asynchronous responsive-scrolling path and would be flaky. Routing is the
/// deterministic half, and the half that broke.
///
/// They are structural mirrors of the editor's nesting, so they do not pin where
/// `inertWhileEditorScrolls()` is applied in the production row — only review does.
@Suite(.serialized)
@MainActor
struct EditorRowsScrollHitTestingTests {

    /// Pre-order walk, unlike `MiddleMousePanView`'s walk *up* from a hit view, but the same
    /// `scrollsHorizontally` predicate.
    private func firstHorizontalScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView, scrollView.scrollsHorizontally {
            return scrollView
        }
        for subview in view.subviews {
            if let found = firstHorizontalScrollView(in: subview) { return found }
        }
        return nil
    }

    /// `enclosingScrollView` on the hit view is what wheel delivery ends up resolving, so this is
    /// the real invariant.
    private func hitView(over canvas: NSScrollView, in host: NSView) -> NSView? {
        let center = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
        return host.hitTest(canvas.convert(center, to: host.superview))
    }

    /// Both halves of the fix on one tree: the canvas keeps receiving wheel events, *and* the gate
    /// still makes its content inert. Without the second assertion a gate whose environment never
    /// reached it would pass — having quietly deleted the optimization the flag exists for.
    @Test func rowCanvasKeepsReceivingWheelEventsWhileItsContentGoesInert() async throws {
        let scrollState = EditorScrollState()
        let host = NSHostingView(rootView: GateInsideRowHost(scrollState: scrollState))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = makeTestWindow(hosting: host)
        defer { window.close() }
        try await settle(host, window)

        let canvas = try #require(firstHorizontalScrollView(in: host))
        #expect(hitView(over: canvas, in: host) is HitProbe.ProbeView, "idle")

        scrollState.isScrolling = true
        try await settle(host, window)
        #expect(hitView(over: canvas, in: host)?.enclosingScrollView === canvas,
                "the canvas must stay the wheel target")
        #expect(!(hitView(over: canvas, in: host) is HitProbe.ProbeView),
                "its content must go inert")

        scrollState.isScrolling = false
        try await settle(host, window)
        #expect(hitView(over: canvas, in: host) is HitProbe.ProbeView, "live again once it settles")
    }

    /// The regression itself, so the reason the gate had to move below the scroll view is recorded
    /// rather than remembered.
    @Test func gatingTheWholeListTakesTheRowCanvasOutOfTheHitTestTree() async throws {
        let scrollState = EditorScrollState()
        let host = NSHostingView(rootView: GateAroundListHost(scrollState: scrollState))
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
        let window = makeTestWindow(hosting: host)
        defer { window.close() }
        try await settle(host, window)

        let canvas = try #require(firstHorizontalScrollView(in: host))
        #expect(hitView(over: canvas, in: host)?.enclosingScrollView === canvas, "idle")

        scrollState.isScrolling = true
        try await settle(host, window)
        #expect(hitView(over: canvas, in: host)?.enclosingScrollView !== canvas,
                "gating above the nested scroll view is what dropped trackpad deltaX")
    }
}
#endif
