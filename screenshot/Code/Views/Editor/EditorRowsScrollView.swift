import SwiftUI

/// The editor's vertical row list.
///
/// It is its own view so the scroll-phase state below stays here rather than on `ContentView`: a
/// phase change several times per drag would otherwise invalidate the whole editor shell —
/// toolbar, inspector and all.
struct EditorRowsScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    /// Hit testing is switched off for the duration of a scroll. Every shape and every row installs
    /// tracking areas and gesture responders, and while the list is moving AppKit re-derives them on
    /// each display cycle — `-[NSScrollView _updateTrackingAreasWithInvalidCursorRects:]` was one of
    /// the largest costs left in a scrollbar-drag trace. Nothing can be clicked mid-flight anyway.
    @State private var isScrolling = false

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) { content }
                .allowsHitTesting(!isScrolling)
        }
        .onScrollPhaseChange { _, phase in
            setScrolling(phase.movesContent)
        }
    }

    /// Restored without animation: re-enabling hit testing is a structural change to the responder
    /// tree, and any ambient animation reaching this subtree would otherwise drive it.
    private func setScrolling(_ scrolling: Bool) {
        guard scrolling != isScrolling else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isScrolling = scrolling }
    }
}

private extension ScrollPhase {
    /// `.tracking` is deliberately *not* movement: it is the phase where the pointer is down but the
    /// content has not moved yet, so a press that turns out to be a click — not a scroll — has to
    /// keep landing on the shape under it.
    var movesContent: Bool {
        switch self {
        case .interacting, .decelerating, .animating: true
        case .idle, .tracking: false
        @unknown default: false
        }
    }
}
