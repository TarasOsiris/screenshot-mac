import SwiftUI

/// Cmd+scroll zoom. A local `NSEvent` monitor with an explicit lifetime, because SwiftUI has no
/// scroll-wheel gesture; a no-op on iPad, which has no scroll wheel.
@MainActor
final class PlatformScrollWheelZoom {
    private var monitor: Any?
    private weak var state: AppState?

    /// Idempotent — safe to call from a re-entered `onAppear`.
    func install(state: AppState) {
        #if os(macOS)
        guard monitor == nil else { return }
        self.state = state
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            let delta = event.hasPreciseScrollingDeltas
                ? event.scrollingDeltaY * 0.005
                : event.scrollingDeltaY * 0.05
            state.zoom.setContinuous(state.zoom.level + delta)
            return nil
        }
        #endif
    }

    func remove() {
        #if os(macOS)
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        state?.zoom.endContinuous()
        state = nil
        #endif
    }
}

extension View {
    /// Pinch-to-zoom over the canvas. The two platform branches were byte-identical apart from
    /// iPad's view-mode guard, which exists because on iPad an unguarded magnification gesture
    /// competes with the one-finger shape gestures in edit mode.
    ///
    /// Writes go through `setZoomLevelContinuous`, which throttles them: `zoom.level` is read by
    /// every visible row's body.
    func canvasPinchZoom(state: AppState, startLevel: Binding<CGFloat?>) -> some View {
        simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    #if os(iOS)
                    guard state.isViewMode else { return }
                    #endif
                    let base = startLevel.wrappedValue ?? state.zoom.level
                    if startLevel.wrappedValue == nil {
                        startLevel.wrappedValue = base
                    }
                    state.zoom.setContinuous(base * value)
                }
                .onEnded { _ in
                    startLevel.wrappedValue = nil
                    state.zoom.endContinuous()
                }
        )
    }
}
