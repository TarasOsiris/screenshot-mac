import SwiftUI

/// The editor's vertical row list.
///
/// It is its own view so the scroll-phase state below stays here rather than on `ContentView`: a
/// phase change several times per drag would otherwise invalidate the whole editor shell —
/// toolbar, inspector and all.
struct EditorRowsScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    /// Published so each row can make its heavy subtrees inert for the duration of a scroll — see
    /// `inertWhileEditorScrolls()`. Every shape and every row installs tracking areas and gesture
    /// responders, and while the list is moving AppKit re-derives them on each display cycle —
    /// `-[NSScrollView _updateTrackingAreasWithInvalidCursorRects:]` was one of the largest costs
    /// left in a scrollbar-drag trace. Only those subtrees go inert, so row-level clicks (select,
    /// context menu, add-row) still land mid-flight — matching the platform, where a click during
    /// deceleration is meaningful.
    ///
    /// An object rather than a `@State` Bool published through an `EnvironmentKey`: the rows read
    /// this too, and an environment *value* that changes invalidates every view declaring it —
    /// which was all 13 realized rows re-running their bodies on every start and end of a scroll,
    /// pinning the main thread during repeated trackpad flicks. The object's reference never
    /// changes, and a row that has latched its chrome never reads the property.
    @State private var scrollState = EditorScrollState()

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) { content }
                .environment(scrollState)
        }
        .onScrollPhaseChange { _, phase in
            setScrolling(phase.movesContent)
        }
    }

    /// Never animated: an ambient animation reaching the gates below would otherwise drive the
    /// hit-testing flip, which is a structural change to the responder tree.
    private func setScrolling(_ scrolling: Bool) {
        guard scrolling != scrollState.isScrolling else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrollState.isScrolling = scrolling }
    }
}

private extension ScrollPhase {
    /// Only the two phases the *user* is driving.
    ///
    /// `.tracking` is deliberately not one of them: it is the phase where the pointer is down but
    /// the content has not moved yet, so a press that turns out to be a click — not a scroll — has
    /// to keep landing on the shape under it. `.decelerating` is, because trackpad momentum is
    /// exactly when the tracking-area churn hurts, and swallowing a click there matches the
    /// platform (a tap during deceleration stops the scroll rather than activating a control).
    ///
    /// `.animating` is excluded because it is a *programmatic* scroll — `ScrollViewReader.scrollTo`
    /// for the canvas-focus jump, and on iPad the keyboard-avoidance scroll that runs while the
    /// user is editing text. Treating it as movement made the whole row list inert for the duration
    /// of each one.
    var movesContent: Bool {
        switch self {
        case .interacting, .decelerating: true
        case .idle, .tracking, .animating: false
        @unknown default: false
        }
    }
}

/// Whether the editor's row list is being scrolled. See `EditorRowsScrollView.scrollState`.
@Observable
final class EditorScrollState {
    var isScrolling = false
}

private struct EditorScrollHitTestGate: ViewModifier {
    @Environment(EditorScrollState.self) private var scrollState

    func body(content: Content) -> some View {
        content.allowsHitTesting(!scrollState.isScrolling)
    }
}

extension View {
    /// Apply *inside* a nested scroll view, never above one: the gate makes its whole subtree
    /// unroutable for `scrollWheel:`, and AppKit picks the scroll view to scroll by hit test — so
    /// above one it takes that scroll view with it, which is how the row canvases lost trackpad
    /// horizontal scrolling to the vertical list.
    func inertWhileEditorScrolls() -> some View {
        modifier(EditorScrollHitTestGate())
    }
}
