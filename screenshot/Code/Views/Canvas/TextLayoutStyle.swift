import AppKit
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

enum TextLayoutStyle {
    static let defaultLineHeightMultiple: CGFloat = 1.0
    static let lineHeightRange: ClosedRange<CGFloat> = 0.5...2.0

    static func clampLineHeightMultiple(_ value: CGFloat) -> CGFloat {
        min(max(value, lineHeightRange.lowerBound), lineHeightRange.upperBound)
    }

    private static let sharedLayoutManager = NSLayoutManager()

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
        let defaultLineHeight = sharedLayoutManager.defaultLineHeight(for: font)
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
            let defaultLineHeight = sharedLayoutManager.defaultLineHeight(for: font)
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
        let defaultLineHeight = sharedLayoutManager.defaultLineHeight(for: font)
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

    static func renderImage(
        size: CGSize,
        text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlign,
        uppercase: Bool,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        richTextData: String? = nil
    ) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let view = TextLayoutNSView(frame: NSRect(origin: .zero, size: size))
        view.configure(
            text: text,
            font: font,
            color: color,
            alignment: alignment,
            verticalAlignment: verticalAlignment,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData
        )
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
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
}
