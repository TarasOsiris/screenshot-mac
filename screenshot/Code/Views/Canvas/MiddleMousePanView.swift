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

    func install() {
        uninstall()

        let downMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, event.buttonNumber == 2 else { return event }
            guard let window = event.window else { return event }

            // Guard against double mouse-down without intervening mouse-up
            if self.activeScrollView != nil {
                PlatformCursor.release(.pan)
                self.activeScrollView = nil
            }

            let pointInWindow = event.locationInWindow
            guard let hitView = window.contentView?.hitTest(pointInWindow),
                  let scrollView = Self.findHorizontalScrollView(from: hitView) else { return event }

            self.activeScrollView = scrollView
            self.lastDragPoint = pointInWindow
            PlatformCursor.hold(.openHand, for: .pan)
            return nil
        }
        if let downMonitor { monitors.append(downMonitor) }

        let dragMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDragged) { [weak self] event in
            guard let self, event.buttonNumber == 2,
                  let scrollView = self.activeScrollView,
                  let lastPoint = self.lastDragPoint else { return event }

            PlatformCursor.hold(.closedHand, for: .pan)

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
            PlatformCursor.release(.pan)
            return nil
        }
        if let upMonitor { monitors.append(upMonitor) }
    }

    func uninstall() {
        PlatformCursor.release(.pan)
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        activeScrollView = nil
        lastDragPoint = nil
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
