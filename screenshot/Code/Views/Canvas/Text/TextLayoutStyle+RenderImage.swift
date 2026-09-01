#if os(macOS)
import AppKit
#else
import UIKit
#endif

// `renderImage` builds a `TextLayoutNSView`, so it stays in `Views/` while the rest of
// `TextLayoutStyle` — pure TextKit metrics that `RichTextUtils` needs — lives in `Services/Media/`.
// Splitting the type rather than moving it keeps all 23 call sites unchanged.
extension TextLayoutStyle {
    /// Ceiling on the supersample factor. The editor asks for `displayScale × screenScale`, which a
    /// short template at maximum zoom can push past 6 — enough to turn one headline into a
    /// hundred-megabyte raster.
    static let maxTextRenderScale: CGFloat = 3

    #if os(macOS)
    /// What the implicit path produced before the factor became explicit: `bitmapImageRepForCachingDisplay`
    /// hands back a rep at the main screen's backing scale, which is 2× on every Mac this ships to,
    /// while iOS's renderer was pinned to `format.scale = 1`. Preserved per-platform so export bytes
    /// don't move underneath a change that is only meant to make the editor cheaper.
    static let defaultTextRenderScale: CGFloat = 2
    #else
    static let defaultTextRenderScale: CGFloat = 1
    #endif

    /// Integer buckets only: the factor lands in the cache key, and a continuous one would miss on
    /// every zoom step it is meant to survive.
    ///
    /// Floors at 1, **not** at `defaultTextRenderScale`. The default exists to reproduce the bytes
    /// the implicit rasterizer produced for export and preview, which draw at model scale; the
    /// editor shrinks its raster by `displayScale` — around 0.2 for an App Store template — so
    /// holding it to 2 rendered ~5× the pixels the screen can show and pushed the cache past its
    /// byte limit, which put a full TextKit layout back inside body evaluation on every miss.
    static func quantizedTextRenderScale(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite, scale > 1 else { return 1 }
        return min(maxTextRenderScale, scale.rounded(.up))
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
        richTextData: String? = nil,
        renderScale: CGFloat = defaultTextRenderScale
    ) -> NSImage? {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }
        let scale = quantizedTextRenderScale(renderScale)
        let cacheKey = textImageCacheKey(
            size: size, scale: scale, text: text, font: font, color: color, alignment: alignment,
            verticalAlignment: verticalAlignment, uppercase: uppercase, letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData
        ) as NSString
        if let cached = textImageCache.object(forKey: cacheKey) {
            return cached
        }
        guard let image = drawTextImage(
            size: size, scale: scale, text: text, font: font, color: color, alignment: alignment,
            verticalAlignment: verticalAlignment, uppercase: uppercase, letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple, legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData
        ) else { return nil }
        let pixelWidth = max(1, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(1, Int((size.height * scale).rounded(.up)))
        let cost = pixelWidth * pixelHeight * 4
        textImageCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    /// Bounded by bytes as well as count — `countLimit` alone lets a few supersampled headlines pin
    /// far more memory than a few hundred small labels.
    private static let textImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 512
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    #if os(macOS)
    private static func drawTextImage(
        size: CGSize,
        scale: CGFloat,
        text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlign,
        uppercase: Bool,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        richTextData: String?
    ) -> NSImage? {
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
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int((size.width * scale).rounded(.up))),
            pixelsHigh: max(1, Int((size.height * scale).rounded(.up))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            // "Generic RGB" — the space `bitmapImageRepForCachingDisplay` picked. `.deviceRGB` is a
            // different profile and shifted every exported glyph's colour.
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        // Point size, not pixel size: the extra pixels are zoom headroom, and every caller frames
        // the result in model space. This is also what makes the CTM scale points→pixels for us.
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
    #else
    // iPad: lay out the attributed string with TextKit and draw it into an image. Mirrors
    // TextLayoutNSView.draw (which is macOS-only). UIKit's image renderer uses a top-left
    // origin, matching the macOS view's `isFlipped = true`.
    private static func drawTextImage(
        size: CGSize,
        scale: CGFloat,
        text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlign,
        uppercase: Bool,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        richTextData: String?
    ) -> NSImage? {
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

        return PlatformImageRenderer.image(size: size, scale: scale) {
            let origin = CGPoint(x: 0, y: yOffset)
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        }
    }
    #endif

    /// Weight is not recoverable from `fontName` alone for a variable font resolved to an instance,
    /// so it goes in the key explicitly — two weights of one family must not collide.
    private static func fontWeightToken(_ font: NSFont) -> String {
        #if os(macOS)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        #else
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        #endif
        return (traits?[.weight] as? CGFloat).map(scalarToken) ?? "-"
    }

    /// Lossless scalar tokens prevent fractional model-space dimensions and subtly different
    /// styling values from aliasing to one cache entry. `String(format:)` rounding is unsafe here:
    /// even two bounds that round to the same point can require different backing-pixel sizes.
    private static func scalarToken(_ value: CGFloat) -> String {
        String(Double(value).bitPattern, radix: 16)
    }

    private static func colorToken(_ color: NSColor) -> String {
        let cgColor = color.cgColor
        let colorSpace = String(describing: cgColor.colorSpace?.name)
        let components = (cgColor.components ?? []).map(scalarToken).joined(separator: ",")
        return "\(colorSpace),\(cgColor.numberOfComponents),\(components)"
    }

    static func textImageCacheKey(
        size: CGSize, scale: CGFloat, text: String, font: NSFont, color: NSColor,
        alignment: NSTextAlignment, verticalAlignment: TextVerticalAlign, uppercase: Bool,
        letterSpacing: CGFloat?, lineHeightMultiple: CGFloat?, legacyLineSpacing: CGFloat?,
        richTextData: String?
    ) -> String {
        return [
            "\(scalarToken(size.width))x\(scalarToken(size.height))",
            "@\(scalarToken(scale))",
            text, font.fontName, scalarToken(font.pointSize), "\(font.fontDescriptor.symbolicTraits.rawValue)",
            fontWeightToken(font),
            colorToken(color), "\(alignment.rawValue)", "\(verticalAlignment)", "\(uppercase)",
            letterSpacing.map(scalarToken) ?? "-",
            lineHeightMultiple.map(scalarToken) ?? "-",
            legacyLineSpacing.map(scalarToken) ?? "-",
            richTextData ?? "-",
        ].joined(separator: "|")
    }
}
