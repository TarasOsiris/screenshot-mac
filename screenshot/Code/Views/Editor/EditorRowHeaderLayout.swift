import CoreGraphics
import SwiftUI

/// Whether the row header has room for its label and resolution text.
///
/// Replaces a `ViewThatFits` that built and measured *two complete header layouts* — chevron,
/// preview toggle, five `ActionButton`s and a menu each — for every row. That was the
/// `SizeFittingLayoutComputer` / `ViewSizeCache` cost in a scroll trace. Same shape as
/// `TemplateBarLayout`: arithmetic the caller can test, rather than a measured fit.
enum EditorRowHeaderLayout {
    #if os(macOS)
    static let previewSegmentSize = CGSize(width: 24, height: 16)
    static let previewToggleInset: CGFloat = 1
    #else
    static let previewSegmentSize = CGSize(
        width: UIMetrics.ActionButton.frameSize,
        height: UIMetrics.ActionButton.frameSize
    )
    static let previewToggleInset: CGFloat = 0
    #endif

    /// Everything in the header that is not the two text runs: outer padding, the chevron, the
    /// preview toggle, the trailing controls, and the `HStack` gaps between them. Derived from the
    /// header's own metrics; being a few points out only nudges the breakpoint, and the margin
    /// below keeps that erring towards hiding the labels rather than overflowing the row.
    static let fixedChromeWidth: CGFloat = {
        #if os(macOS)
        let chevron: CGFloat = 12
        #else
        let chevron: CGFloat = 28
        #endif
        let previewToggle = previewSegmentSize.width * 2 + previewToggleInset * 2
        let button = UIMetrics.ActionButton.frameSize
        // Five action buttons at spacing 4, then the ellipsis menu.
        let trailing = button * 5 + 4 * 4 + 4 + button
        let outerPadding: CGFloat = 16 * 2
        let gaps: CGFloat = 8 * 5
        return outerPadding + chevron + previewToggle + trailing + gaps
    }()

    /// Kept clear so a slightly optimistic estimate hides the labels rather than pushing the
    /// trailing controls off the row — the labels are `fixedSize`, so they do not compress.
    private static let margin: CGFloat = 8

    static func showsLabels(availableWidth: CGFloat, labelsWidth: CGFloat) -> Bool {
        // Zero means "not measured yet"; show the labels rather than flashing the compact layout.
        guard availableWidth > 0 else { return true }
        return labelsWidth + margin <= availableWidth - fixedChromeWidth
    }

    /// Rendered width of a string at a given system font, for `showsLabels(availableWidth:labelsWidth:)`.
    static func textWidth(_ string: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return NSAttributedString(string: string, attributes: [.font: font]).size().width
    }
}

private struct EditorViewportWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Width of the editor's row viewport, measured once by `ContentView`. One measurement for the
    /// whole list instead of a two-candidate fit per row.
    var editorViewportWidth: CGFloat {
        get { self[EditorViewportWidthKey.self] }
        set { self[EditorViewportWidthKey.self] = newValue }
    }
}
