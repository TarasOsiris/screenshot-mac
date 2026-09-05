import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Modifier that enables middle-mouse-button drag to pan horizontal scroll views
/// (Figma-style hand tool). Attach once at the top level. No-op on iOS (touch panning
/// is native).
struct MiddleMousePanModifier: ViewModifier {
#if os(macOS)
    @State private var coordinator = PanCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.install() }
            .onDisappear { coordinator.uninstall() }
    }
#else
    func body(content: Content) -> some View { content }
#endif
}

#if os(macOS)
@MainActor
private final class PanCoordinator {
    private var monitors: [Any] = []
    private var lastDragPoint: NSPoint?
    private weak var activeScrollView: NSScrollView?
    private var hasDragged = false
    /// Tracks whether we currently have a cursor pushed onto the stack, so
    /// push/pop always balance regardless of the order mouse events arrive in.
    private var didPushCursor = false

    private func popCursorIfNeeded() {
        if didPushCursor {
            NSCursor.pop()
            didPushCursor = false
        }
    }

    func install() {
        uninstall()

        let downMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 2 else { return event }
            guard let window = event.window else { return event }

            // Guard against double mouse-down without intervening mouse-up
            if self.activeScrollView != nil {
                self.popCursorIfNeeded()
                self.activeScrollView = nil
            }

            let pointInWindow = event.locationInWindow
            guard let hitView = window.contentView?.hitTest(pointInWindow),
                  let scrollView = Self.findHorizontalScrollView(from: hitView) else { return event }

            self.activeScrollView = scrollView
            self.lastDragPoint = pointInWindow
            self.hasDragged = false
            NSCursor.openHand.push()
            self.didPushCursor = true
            return nil
        }
        if let downMonitor { monitors.append(downMonitor) }

        let dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { [weak self] event in
            guard let self, event.buttonNumber == 2,
                  let scrollView = self.activeScrollView,
                  let lastPoint = self.lastDragPoint else { return event }

            // Switch from open hand to closed hand on first drag movement
            if !self.hasDragged {
                self.hasDragged = true
                self.popCursorIfNeeded()
                NSCursor.closedHand.push()
                self.didPushCursor = true
            }

            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - lastPoint.x

            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            origin.x -= deltaX
            origin.x = min(max(0, origin.x), scrollView.maxHorizontalScrollOffset)
            clipView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clipView)

            self.lastDragPoint = currentPoint
            return nil
        }
        if let dragMonitor { monitors.append(dragMonitor) }

        let upMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseUp) { [weak self] event in
            guard let self, event.buttonNumber == 2, self.activeScrollView != nil else { return event }
            self.activeScrollView = nil
            self.lastDragPoint = nil
            self.hasDragged = false
            self.popCursorIfNeeded()
            return nil
        }
        if let upMonitor { monitors.append(upMonitor) }
    }

    func uninstall() {
        // Pop cursor if one is still pushed from an active drag session
        popCursorIfNeeded()
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        activeScrollView = nil
        lastDragPoint = nil
        hasDragged = false
    }

    /// Walk up from the hit view to find the nearest horizontal-scrolling NSScrollView.
    private static func findHorizontalScrollView(from view: NSView) -> NSScrollView? {
        var current: NSView? = view
        while let v = current {
            if let sv = v as? NSScrollView, sv.contentIsWiderThanViewport { return sv }
            current = v.superview
        }
        return nil
    }
}

extension NSScrollView {
    var maxHorizontalScrollOffset: CGFloat {
        max(0, (documentView?.frame.width ?? 0) - contentView.bounds.width)
    }

    var contentIsWiderThanViewport: Bool { maxHorizontalScrollOffset > 0 }
}
#endif

extension View {
    func middleMousePan() -> some View {
        modifier(MiddleMousePanModifier())
    }
}
