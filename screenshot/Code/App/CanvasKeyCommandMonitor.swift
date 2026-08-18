#if os(macOS)
import AppKit
#endif
import Foundation

/// Arrow-key nudge and Delete for canvas shapes, via a local `NSEvent` monitor.
///
/// A monitor is used rather than SwiftUI key handling so the shortcuts work without a focused
/// first responder while still passing through to text fields. On iPad these are deferred to
/// on-screen controls, so this installs nothing.
///
/// Lived on `AppState`, which meant an `@Observable` document object owned an AppKit event
/// monitor and a manual `deinit`.
@MainActor
final class CanvasKeyCommandMonitor {
    /// What the monitor needs from whoever owns the canvas. Built with `[weak self]` captures at
    /// the call site — see the warning on `install`.
    struct Handlers {
        var hasSelection: () -> Bool
        var isEditingText: () -> Bool
        var nudge: (CGFloat, CGFloat) -> Void
        var delete: () -> Void
    }

    /// `nonisolated(unsafe)` because `deinit` is nonisolated even on a `@MainActor` class, and it
    /// has to be able to remove the monitor.
    nonisolated(unsafe) private var monitor: Any?

    /// ⚠️ The handlers must capture their owner weakly. This object is owned by `AppState`, so
    /// handlers that capture `AppState` strongly form a cycle that nothing breaks — every
    /// `AppState` in the test suite would leak *and* leave a live local `NSEvent` monitor
    /// installed, mutating a state the test believes is gone.
    func install(_ handlers: Handlers) {
        #if os(macOS)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Let text fields have the keystroke.
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            guard handlers.hasSelection(), !handlers.isEditingText() else { return event }
            let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
            switch event.keyCode {
            case PlatformKeyCode.LeftArrow:  handlers.nudge(-step, 0); return nil
            case PlatformKeyCode.RightArrow: handlers.nudge(step, 0); return nil
            case PlatformKeyCode.UpArrow:    handlers.nudge(0, -step); return nil
            case PlatformKeyCode.DownArrow:  handlers.nudge(0, step); return nil
            case PlatformKeyCode.Delete, PlatformKeyCode.ForwardDelete: handlers.delete(); return nil
            default: return event
            }
        }
        #endif
    }

    deinit {
        #if os(macOS)
        if let monitor { NSEvent.removeMonitor(monitor) }
        #endif
    }
}
