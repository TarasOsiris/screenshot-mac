#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The inputs `TextLayoutStyle.renderImage` lays out, gathered so a fit check and the raster it
/// predicts can never be handed different values.
struct TextFitInput {
    var size: CGSize
    var text: String
    var font: NSFont
    var alignment: NSTextAlignment
    var uppercase: Bool
    var letterSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?
    var legacyLineSpacing: CGFloat?
    var richTextData: String?

    /// Two weights of one variable font share a PostScript name, so the weight is keyed on its own.
    private static func weightToken(_ font: NSFont) -> String {
        #if os(macOS)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        #else
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        #endif
        return (traits?[.weight] as? CGFloat).map { "\($0)" } ?? "-"
    }

    /// The inputs the canvas lays out for a text shape that is already resolved for its locale.
    init(shape: CanvasShapeModel, availableFontFamilies: Set<String>) {
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = CSSFontWeight(css: shape.fontWeight ?? 700).platform
        self.init(
            size: CGSize(width: shape.width, height: shape.height),
            text: shape.text ?? "",
            font: TextFontResolver.resolvedFont(
                shape: shape, availableFontFamilies: availableFontFamilies,
                size: fontSize, weight: weight, italic: shape.italic ?? false
            ),
            alignment: shape.textAlign.nsTextAlignment,
            uppercase: shape.uppercase ?? false,
            letterSpacing: shape.letterSpacing,
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            richTextData: shape.richText
        )
    }

    init(
        size: CGSize, text: String, font: NSFont, alignment: NSTextAlignment, uppercase: Bool,
        letterSpacing: CGFloat?, lineHeightMultiple: CGFloat?, legacyLineSpacing: CGFloat?,
        richTextData: String?
    ) {
        self.size = size
        self.text = text
        self.font = font
        self.alignment = alignment
        self.uppercase = uppercase
        self.letterSpacing = letterSpacing
        self.lineHeightMultiple = lineHeightMultiple
        self.legacyLineSpacing = legacyLineSpacing
        self.richTextData = richTextData
    }

    fileprivate var cacheKey: String {
        [
            "\(size.width)x\(size.height)", text, font.fontName, "\(font.pointSize)",
            "\(font.fontDescriptor.symbolicTraits.rawValue)", Self.weightToken(font), "\(alignment.rawValue)", "\(uppercase)",
            letterSpacing.map { "\($0)" } ?? "-", lineHeightMultiple.map { "\($0)" } ?? "-",
            legacyLineSpacing.map { "\($0)" } ?? "-", richTextData ?? "-",
        ].joined(separator: "|")
    }
}

enum TextFitMeasurer {
    static let minimumShrinkScale: CGFloat = 0.5
    private static let searchSteps = 8

    /// Whether every glyph gets a line fragment in the renderer's container. The renderer lays out
    /// into exactly the shape's box, and TextKit silently drops lines that don't fit — so this is
    /// the same test the raster applies, not an estimate of it.
    static func fits(_ input: TextFitInput, fontScale: CGFloat = 1) -> Bool {
        guard input.size.width > 0, input.size.height > 0 else { return true }
        let attributed = RichTextUtils.buildAttributedString(
            richText: input.richTextData,
            plainText: input.text,
            font: input.font,
            color: .black,
            alignment: input.alignment,
            letterSpacing: input.letterSpacing,
            lineHeightMultiple: input.lineHeightMultiple,
            legacyLineSpacing: input.legacyLineSpacing,
            uppercase: input.uppercase,
            fontScale: fontScale
        )
        guard attributed.length > 0 else { return true }
        let storage = NSTextStorage(attributedString: attributed)
        let layoutManager = NSLayoutManager()
        let compactDelegate = CompactLineLayoutDelegate()
        compactDelegate.lineHeightMultiple = input.lineHeightMultiple ?? 1.0
        layoutManager.delegate = compactDelegate
        let container = NSTextContainer(size: input.size)
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let laidOut = layoutManager.glyphRange(for: container)
        return NSMaxRange(laidOut) >= layoutManager.numberOfGlyphs
    }

    /// The largest font scale in `minimumShrinkScale...1` at which the text fits, or
    /// `minimumShrinkScale` when even that overflows.
    static func fitScale(_ input: TextFitInput) -> CGFloat {
        let key = input.cacheKey as NSString
        if let cached = fitScaleCache.object(forKey: key) {
            return CGFloat(cached.doubleValue)
        }
        let scale = searchFitScale(input)
        fitScaleCache.setObject(NSNumber(value: Double(scale)), forKey: key)
        return scale
    }

    /// Whether the rendered text loses lines: at full size, or — for a shrink-to-fit shape — even
    /// at the smallest scale shrinking may use.
    static func overflows(_ input: TextFitInput, shrinksToFit: Bool) -> Bool {
        let key = "\(shrinksToFit)|\(input.cacheKey)" as NSString
        if let cached = overflowCache.object(forKey: key) {
            return cached.boolValue
        }
        let fontScale = shrinksToFit ? fitScale(input) : 1
        let result = !fits(input, fontScale: fontScale)
        overflowCache.setObject(NSNumber(value: result), forKey: key)
        return result
    }

    private static func searchFitScale(_ input: TextFitInput) -> CGFloat {
        if fits(input) { return 1 }
        var low = minimumShrinkScale
        var high: CGFloat = 1
        guard fits(input, fontScale: low) else { return low }
        for _ in 0..<searchSteps {
            let mid = (low + high) / 2
            if fits(input, fontScale: mid) {
                low = mid
            } else {
                high = mid
            }
        }
        return low
    }

    private static let overflowCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()

    private static let fitScaleCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 1024
        return cache
    }()
}
