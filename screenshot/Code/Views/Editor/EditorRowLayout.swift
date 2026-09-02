import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The exact height of one editor row, stated rather than measured.
///
/// The editor's `LazyVStack` has to know how tall every row is before it can place any of them.
/// Letting it find that out by measuring meant descending through each row's header, its horizontal
/// `ScrollView`, the padding chain and the control bars — which a scrollbar-drag trace showed was
/// the single largest main-thread cost, with *zero* view bodies being evaluated. Every piece of a
/// row already carries an explicit frame, so the total is knowable up front; this is where that
/// knowledge lives.
///
/// `EditorRowLayoutTests` measures the real views against these numbers, so a change to the header
/// or the control bars fails a test rather than silently clipping.
enum EditorRowLayout {
    /// `EditorRowHeader` is one row of `ActionButton`-sized controls inside its own insets.
    static let headerContentHeight: CGFloat = UIMetrics.ActionButton.frameSize
    static let headerInsets = EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16)
    static var headerHeight: CGFloat { headerContentHeight + headerInsets.top + headerInsets.bottom }

    /// Insets around the canvas strip inside the horizontal scroll view.
    static let scrollContentInsets = EdgeInsets(top: 4, leading: 16, bottom: 12, trailing: 16)
    /// Gap between the control bars and the bottom of the scroll content.
    static let controlBarsBottomInset: CGFloat = 8

    /// Legacy scrollers ("Show scroll bars: Always") are laid out *inside* the scroll view and take
    /// height from its content; overlay scrollers float above it and take none. The scroll area used
    /// to absorb this by sizing itself — now that its height is stated, the allowance has to be
    /// stated too, or that setting clips the bottom of the control bars.
    static var horizontalScrollerHeight: CGFloat {
        #if os(macOS)
        // Through the monitor, not `NSScroller` directly: the style changes while the app runs, and
        // a *stated* height only follows it if the read is observable from the body that states it.
        guard ScrollerStyleMonitor.shared.style == .legacy else { return 0 }
        return NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        #else
        return 0
        #endif
    }

    /// Height of the horizontal scroll area: the canvas, plus the per-template control bars in edit
    /// mode (preview mode has none), plus the insets and any legacy scroller.
    static func scrollAreaHeight(row: ScreenshotRow, zoom: CGFloat, isPreviewMode: Bool) -> CGFloat {
        let controlBars = isPreviewMode ? 0 : UIMetrics.TemplateBar.height + controlBarsBottomInset
        return row.displayHeight(zoom: zoom)
            + controlBars
            + scrollContentInsets.top
            + scrollContentInsets.bottom
            + horizontalScrollerHeight
    }

    /// The row's full height, which is what the `LazyVStack` places against.
    static func rowHeight(row: ScreenshotRow, zoom: CGFloat, isPreviewMode: Bool) -> CGFloat {
        guard !row.isCollapsed else { return headerHeight }
        return headerHeight + scrollAreaHeight(row: row, zoom: zoom, isPreviewMode: isPreviewMode)
    }

    // The `Divider` between rows is deliberately not part of this contract. It is a leaf primitive
    // with an intrinsic height and no children, so the stack already sizes it without descending
    // into anything — which is the only cost this type exists to remove.
}

#if os(macOS)
/// `NSScroller.preferredScrollerStyle` as observable state.
///
/// With "Show scroll bars: Automatically", plugging in a mouse flips AppKit to legacy scrollers
/// mid-session. A measured row would absorb that; a stated one cannot, so every realized row would
/// keep a height that no longer matches its scroller and clip the control bars until some unrelated
/// edit re-ran its body. Reading the style through this in `horizontalScrollerHeight` puts it in the
/// tracking scope of `EditorRowView.body`, which is what states the height.
@Observable @MainActor
final class ScrollerStyleMonitor {
    static let shared = ScrollerStyleMonitor()

    private(set) var style = NSScroller.preferredScrollerStyle

    private init() {
        // `queue: nil` — the notification is posted on the main thread, and a queued block would
        // land a frame later than the scrollers it describes.
        NotificationCenter.default.addObserver(
            forName: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                let current = NSScroller.preferredScrollerStyle
                guard let self, self.style != current else { return }
                self.style = current
            }
        }
    }
}
#endif
