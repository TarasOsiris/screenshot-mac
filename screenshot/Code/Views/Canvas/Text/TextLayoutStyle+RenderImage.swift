#if os(macOS)
import AppKit
#else
import UIKit
#endif

// `renderImage` builds a `TextLayoutNSView`, so it stays in `Views/` while the rest of
// `TextLayoutStyle` — pure TextKit metrics that `RichTextUtils` needs — lives in `Services/Media/`.
// Splitting the type rather than moving it keeps all 23 call sites unchanged.
extension TextLayoutStyle {
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
        let yOffset = verticalOffset(
            containerHeight: size.height,
            contentHeight: usedRect.height,
            padding: padding,
            alignment: verticalAlignment
        )

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
}
