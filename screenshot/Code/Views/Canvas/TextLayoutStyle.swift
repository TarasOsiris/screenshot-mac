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
        #if os(macOS)
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
        #else
        // iPad: lay out the attributed string with TextKit and draw it into an image. Mirrors
        // TextLayoutNSView.draw (which is macOS-only). UIKit's image renderer uses a top-left
        // origin, matching the macOS view's `isFlipped = true`. This is the live-canvas text
        // path on iPad (no persistent NSTextView), so results are memoized to avoid rebuilding
        // a TextKit stack + re-rasterizing on every zoom/scroll re-layout.
        let cacheKey = iosTextImageCacheKey(
            size: size, text: text, font: font, color: color, alignment: alignment,
            verticalAlignment: verticalAlignment, uppercase: uppercase, letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData
        ) as NSString
        if let cached = iosTextImageCache.object(forKey: cacheKey) {
            return cached
        }

        let attributed = RichTextUtils.buildAttributedString(
            richText: richTextData,
            plainText: text,
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            uppercase: uppercase
        )
        let textStorage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let compactDelegate = CompactLineLayoutDelegate()
        compactDelegate.lineHeightMultiple = lineHeightMultiple ?? 1.0
        layoutManager.delegate = compactDelegate
        let textContainer = NSTextContainer(size: size)
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let padding = verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )
        let paddedTextHeight = usedRect.height + padding * 2
        let yOffset: CGFloat = switch verticalAlignment {
        case .top: padding
        case .center: max(0, (size.height - paddedTextHeight) / 2) + padding
        case .bottom: max(0, size.height - paddedTextHeight) + padding
        }

        let image = PlatformImageRenderer.image(size: size) {
            let origin = CGPoint(x: 0, y: yOffset)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }
        iosTextImageCache.setObject(image, forKey: cacheKey)
        return image
        #endif
    }

    #if os(iOS)
    private static let iosTextImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 256
        return cache
    }()

    private static func iosTextImageCacheKey(
        size: CGSize, text: String, font: NSFont, color: NSColor, alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlign, uppercase: Bool, letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?, legacyLineSpacing: CGFloat?, richTextData: String?
    ) -> String {
        let traits = (font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any])
        let weight = (traits?[.weight] as? CGFloat).map { String(format: "%.2f", $0) } ?? "-"
        let colorDesc = color.cgColor.components?.map { String(format: "%.3f", $0) }.joined(separator: ",") ?? "?"
        return [
            "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))",
            text, font.fontName, "\(font.pointSize)", "\(font.fontDescriptor.symbolicTraits.rawValue)", weight,
            colorDesc, "\(alignment.rawValue)", "\(verticalAlignment)", "\(uppercase)",
            letterSpacing.map { "\($0)" } ?? "-",
            lineHeightMultiple.map { "\($0)" } ?? "-",
            legacyLineSpacing.map { "\($0)" } ?? "-",
            richTextData ?? "-",
        ].joined(separator: "|")
    }
    #endif

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
