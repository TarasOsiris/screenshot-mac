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
        guard NSScroller.preferredScrollerStyle == .legacy else { return 0 }
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
