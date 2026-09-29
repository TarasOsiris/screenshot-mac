#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Layout manager delegate that compresses line spacing for lineHeightMultiple < 1.0
/// without clipping glyphs. Instead of setting paragraphStyle.lineHeightMultiple (which
/// shrinks line fragment rects and clips ascenders), this delegate keeps full-height
/// fragments and repositions them at the desired compressed y-positions.
final class CompactLineLayoutDelegate: NSObject, NSLayoutManagerDelegate {
    var lineHeightMultiple: CGFloat = 1.0
    private var nextCompressedY: CGFloat = 0

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        guard lineHeightMultiple < 1.0 else { return false }

        let naturalHeight = lineFragmentRect.pointee.height
        guard naturalHeight > 0 else { return false }

        if lineFragmentRect.pointee.origin.y == 0 {
            nextCompressedY = 0
        }

        let desiredSpacing = naturalHeight * lineHeightMultiple
        let delta = nextCompressedY - lineFragmentRect.pointee.origin.y

        lineFragmentRect.pointee.origin.y += delta
        lineFragmentUsedRect.pointee.origin.y += delta

        nextCompressedY += desiredSpacing

        return true
    }
}

/// A glyph outline drawn under the fill; `width` is the visible band outside the glyphs, in model points.
struct TextStroke: Equatable {
    var color: NSColor
    var width: CGFloat

    /// Whole points of margin the raster needs so the band isn't clipped at the box edge.
    var rasterPadding: CGFloat { ceil(max(0, width)) }
}

/// Replaces the glyph fill for the gradient layers.
enum TextGlyphFill: Equatable {
    /// No glyph fill: only highlights and the outline, drawn under a gradient.
    case clear
    /// Opaque glyphs and nothing else — the gradient's mask.
    case mask
}

enum TextLayoutStyle {
    static let defaultLineHeightMultiple: CGFloat = 1.0
    static let lineHeightRange: ClosedRange<CGFloat> = 0.5...2.0

    static func clampLineHeightMultiple(_ value: CGFloat) -> CGFloat {
        min(max(value, lineHeightRange.lowerBound), lineHeightRange.upperBound)
    }

    private static let sharedLayoutManager = NSLayoutManager()

    private static func defaultLineHeight(for font: NSFont) -> CGFloat {
        #if os(macOS)
        return sharedLayoutManager.defaultLineHeight(for: font)
        #else
        return font.lineHeight
        #endif
    }

    static func effectiveLineHeightMultiple(
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        font: NSFont
    ) -> CGFloat {
        if let lineHeightMultiple {
            return clampLineHeightMultiple(lineHeightMultiple)
        }
        guard let legacyLineSpacing, legacyLineSpacing != 0 else {
            return defaultLineHeightMultiple
        }
        let defaultLineHeight = defaultLineHeight(for: font)
        guard defaultLineHeight > 0 else {
            return defaultLineHeightMultiple
        }
        return clampLineHeightMultiple((defaultLineHeight + legacyLineSpacing) / defaultLineHeight)
    }

    static func effectiveLineSpacing(
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        font: NSFont
    ) -> CGFloat {
        if let lineHeightMultiple {
            let defaultLineHeight = defaultLineHeight(for: font)
            guard defaultLineHeight > 0 else { return 0 }
            return defaultLineHeight * (clampLineHeightMultiple(lineHeightMultiple) - 1)
        }
        return legacyLineSpacing ?? 0
    }

    static func verticalGlyphPadding(
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        font: NSFont
    ) -> CGFloat {
        let defaultLineHeight = defaultLineHeight(for: font)
        guard defaultLineHeight > 0 else { return 0 }

        let effectiveLineHeight: CGFloat
        if let lineHeightMultiple {
            // For < 1.0, CompactLineLayoutDelegate keeps full-height line fragments,
            // so no glyph padding is needed.
            guard lineHeightMultiple >= 1.0 else { return 0 }
            effectiveLineHeight = defaultLineHeight * clampLineHeightMultiple(lineHeightMultiple)
        } else {
            effectiveLineHeight = defaultLineHeight + (legacyLineSpacing ?? 0)
        }

        guard effectiveLineHeight < defaultLineHeight else { return 0 }
        return ceil((defaultLineHeight - effectiveLineHeight) / 2) + 5
    }

    static func baselineOffset(
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        font: NSFont
    ) -> CGFloat {
        let padding = verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )
        guard padding > 0 else { return 0 }
        return -padding
    }

    static func editorVerticalPadding(
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        font: NSFont
    ) -> CGFloat {
        let padding = verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )
        guard padding > 0 else { return 0 }
        return padding + ceil(font.ascender * 0.2) + 4
    }

    /// Vertical offset to place a text block of `contentHeight` within a box of `containerHeight`,
    /// honoring top/center/bottom alignment and symmetric glyph `padding`. Shared by the rendered
    /// display path and the iPad live editor so the editor overlay stays pixel-aligned.
    static func verticalOffset(
        containerHeight: CGFloat,
        contentHeight: CGFloat,
        padding: CGFloat,
        alignment: TextVerticalAlign
    ) -> CGFloat {
        let paddedHeight = contentHeight + padding * 2
        return switch alignment {
        case .top: padding
        case .center: max(0, (containerHeight - paddedHeight) / 2) + padding
        case .bottom: max(0, containerHeight - paddedHeight) + padding
        }
    }

    static func paragraphStyle(
        alignment: NSTextAlignment,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        if let lineHeightMultiple {
            // For < 1.0, don't set lineHeightMultiple on the paragraph style — it shrinks
            // line fragment rects and causes glyph clipping. CompactLineLayoutDelegate
            // handles the compressed positioning instead.
            if lineHeightMultiple >= 1.0 {
                style.lineHeightMultiple = lineHeightMultiple
            }
        } else if let legacyLineSpacing {
            style.lineSpacing = legacyLineSpacing
        }
        return style
    }

    static func textAttributes(
        font: NSFont? = nil,
        color: NSColor? = nil,
        alignment: NSTextAlignment,
        letterSpacing: CGFloat? = nil,
        includeBaselineOffset: Bool = true,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?
    ) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle(
                alignment: alignment,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing
            )
        ]
        if let font {
            attributes[.font] = font
            if includeBaselineOffset {
                let baselineOffset = baselineOffset(
                    lineHeightMultiple: lineHeightMultiple,
                    legacyLineSpacing: legacyLineSpacing,
                    font: font
                )
                if baselineOffset != 0 {
                    attributes[.baselineOffset] = baselineOffset
                }
            }
        }
        if let color {
            attributes[.foregroundColor] = color
        }
        if let letterSpacing {
            attributes[.kern] = letterSpacing
        }
        return attributes
    }

    // MARK: - Glyph outline

    /// Strokes every run so the visible band outside the glyphs is `width` model points: AppKit's
    /// stroke width is a percentage of each run's point size and straddles the glyph edge.
    static func applyStroke(to storage: NSTextStorage, color: NSColor, width: CGFloat) {
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            let pointSize = (value as? NSFont)?.pointSize ?? CanvasShapeModel.defaultFontSize
            guard pointSize > 0 else { return }
            storage.addAttributes([
                .strokeColor: color,
                .strokeWidth: 2 * width / pointSize * 100,
            ], range: range)
        }
        storage.endEditing()
    }

    static func removeStroke(from storage: NSTextStorage) {
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.removeAttribute(.strokeColor, range: fullRange)
        storage.removeAttribute(.strokeWidth, range: fullRange)
        storage.endEditing()
    }

    /// One glyph fill over every run, rich-text colors included.
    static func overridingForeground(_ attributed: NSAttributedString, with fill: TextGlyphFill?) -> NSAttributedString {
        guard let fill else { return attributed }
        let result = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: result.length)
        switch fill {
        case .clear:
            result.addAttribute(.foregroundColor, value: NSColor.clear, range: fullRange)
        case .mask:
            result.addAttribute(.foregroundColor, value: NSColor.white, range: fullRange)
            result.removeAttribute(.backgroundColor, range: fullRange)
        }
        return result
    }
}
