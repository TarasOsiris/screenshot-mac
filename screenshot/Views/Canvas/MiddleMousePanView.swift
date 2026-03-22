import SwiftUI
import AppKit

/// Modifier that enables middle-mouse-button drag to pan horizontal scroll views
/// (Figma-style hand tool). Attach once at the top level.
struct MiddleMousePanModifier: ViewModifier {
    @State private var coordinator = PanCoordinator()

    func body(content: Content) -> some View {
        content
            .onAppear { coordinator.install() }
            .onDisappear { coordinator.uninstall() }
    }
}

@MainActor
private final class PanCoordinator {
    private var monitors: [Any] = []
    private var lastDragPoint: NSPoint?
    private weak var activeScrollView: NSScrollView?
    private var hasDragged = false

    func install() {
        uninstall()

        let downMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 2 else { return event }
            guard let window = event.window else { return event }

            // Guard against double mouse-down without intervening mouse-up
            if self.activeScrollView != nil {
                NSCursor.pop()
                self.activeScrollView = nil
            }

            let pointInWindow = event.locationInWindow
            guard let hitView = window.contentView?.hitTest(pointInWindow),
                  let scrollView = Self.findHorizontalScrollView(from: hitView) else { return event }

            self.activeScrollView = scrollView
            self.lastDragPoint = pointInWindow
            self.hasDragged = false
            NSCursor.openHand.push()
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
                NSCursor.pop()
                NSCursor.closedHand.push()
            }

            let currentPoint = event.locationInWindow
            let deltaX = currentPoint.x - lastPoint.x

            let clipView = scrollView.contentView
            var origin = clipView.bounds.origin
            origin.x -= deltaX
            // Clamp to document bounds
            if let docView = scrollView.documentView {
                let maxX = max(0, docView.frame.width - clipView.bounds.width)
                origin.x = min(max(0, origin.x), maxX)
            }
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
            NSCursor.pop()
            return nil
        }
        if let upMonitor { monitors.append(upMonitor) }
    }

    func uninstall() {
        // Pop cursor if a drag session is still active
        if activeScrollView != nil {
            NSCursor.pop()
        }
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
            if let sv = v as? NSScrollView,
               let doc = sv.documentView,
               doc.frame.width > sv.contentView.bounds.width {
                return sv
            }
            current = v.superview
        }
        return nil
    }
}

extension View {
    func middleMousePan() -> some View {
        modifier(MiddleMousePanModifier())
    }
}
