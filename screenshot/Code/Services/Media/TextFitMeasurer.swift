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
}

extension TextFitInput {
    /// A text shape, already resolved for its locale, laid out in `font`. The canvas passes the
    /// font its own resolver produced and adjusts `size`/`text` for live geometry and placeholders.
    init(shape: CanvasShapeModel, font: NSFont) {
        size = CGSize(width: shape.width, height: shape.height)
        text = shape.text ?? ""
        self.font = font
        alignment = shape.textAlign.nsTextAlignment
        uppercase = shape.uppercase ?? false
        letterSpacing = shape.letterSpacing
        lineHeightMultiple = shape.lineHeightMultiple
        legacyLineSpacing = shape.lineSpacing
        richTextData = shape.richText
    }

    init(shape: CanvasShapeModel, availableFontFamilies: Set<String>) {
        let font = TextFontResolver.resolvedFont(
            shape: shape, availableFontFamilies: availableFontFamilies,
            size: shape.fontSize ?? CanvasShapeModel.defaultFontSize,
            weight: CSSFontWeight(css: shape.fontWeight ?? 700).platform,
            italic: shape.italic ?? false
        )
        self.init(shape: shape, font: font)
    }

    fileprivate var cacheKey: String {
        let parts: [String] = [
            "\(TextLayoutStyle.scalarToken(size.width))x\(TextLayoutStyle.scalarToken(size.height))",
            text, font.fontName, TextLayoutStyle.scalarToken(font.pointSize),
            "\(font.fontDescriptor.symbolicTraits.rawValue)", TextLayoutStyle.fontWeightToken(font),
            "\(alignment.rawValue)", "\(uppercase)",
            letterSpacing.map(TextLayoutStyle.scalarToken) ?? "-",
            lineHeightMultiple.map(TextLayoutStyle.scalarToken) ?? "-",
            legacyLineSpacing.map(TextLayoutStyle.scalarToken) ?? "-",
            richTextData ?? "-",
        ]
        return parts.joined(separator: "|")
    }

    fileprivate func attributedString() -> NSAttributedString {
        RichTextUtils.buildAttributedString(
            richText: richTextData, plainText: text, font: font, color: .black, alignment: alignment,
            letterSpacing: letterSpacing, lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing, uppercase: uppercase
        )
    }
}

enum TextFitMeasurer {
    static let minimumShrinkScale: CGFloat = 0.5

    /// Whether every glyph gets a line fragment in the renderer's container. The renderer lays out
    /// into exactly the shape's box, and TextKit silently drops lines that don't fit — so this is
    /// the same test the raster applies, not an estimate of it.
    static func fits(_ input: TextFitInput, fontScale: CGFloat = 1) -> Bool {
        TextFitLayout(input).fits(fontScale: fontScale, height: input.size.height)
    }

    /// The largest font scale in `minimumShrinkScale...1` at which the text fits, or
    /// `minimumShrinkScale` when even that overflows.
    ///
    /// `cachesResult: false` during a live resize or slider burst: every tick is a new key whose
    /// answer is dead on the next one, and storing them would evict every settled shape's fit.
    static func fitScale(_ input: TextFitInput, cachesResult: Bool = true) -> CGFloat {
        fit(input, cachesResult: cachesResult).scale
    }

    /// Whether the rendered text loses lines: at full size, or — for a shrink-to-fit shape — even
    /// at the smallest scale shrinking may use.
    static func overflows(_ input: TextFitInput, shrinksToFit: Bool) -> Bool {
        guard shrinksToFit else {
            let key = input.cacheKey as NSString
            if let cached = overflowCache.object(forKey: key) { return cached.boolValue }
            let result = !fits(input)
            overflowCache.setObject(NSNumber(value: result), forKey: key)
            return result
        }
        return !fit(input, cachesResult: true).fits
    }

    private static func fit(_ input: TextFitInput, cachesResult: Bool) -> (scale: CGFloat, fits: Bool) {
        let key = input.cacheKey as NSString
        if let cached = fitCache.object(forKey: key) { return cached.value }
        let result = searchFitScale(input)
        if cachesResult { fitCache.setObject(FitResult(result), forKey: key) }
        return result
    }

    /// One attributed string and one TextKit stack for the whole search; each step only rescales.
    private static func searchFitScale(_ input: TextFitInput) -> (scale: CGFloat, fits: Bool) {
        TextFitLayout(input).largestFittingScale(height: input.size.height)
    }

    private final class FitResult {
        let value: (scale: CGFloat, fits: Bool)
        init(_ value: (scale: CGFloat, fits: Bool)) { self.value = value }
    }

    private static let overflowCache: NSCache<NSString, NSNumber> = {
        let cache = NSCache<NSString, NSNumber>()
        cache.countLimit = 2048
        return cache
    }()

    private static let fitCache: NSCache<NSString, FitResult> = {
        let cache = NSCache<NSString, FitResult>()
        cache.countLimit = 2048
        return cache
    }()
}

/// One text laid out once, probed at any font scale and box height — for a search that would
/// otherwise rebuild the attributed string and TextKit stack per step.
final class TextFitLayout {
    private static let scaleSearchSteps = 8
    private static let heightSearchSteps = 14

    private let base: NSAttributedString
    private let stack: TextLayoutStack
    private var laidOutScale: CGFloat?

    init(_ input: TextFitInput) {
        base = input.attributedString()
        stack = TextLayoutStack(containerSize: input.size, lineHeightMultiple: input.lineHeightMultiple)
    }

    func fits(fontScale: CGFloat, height: CGFloat) -> Bool {
        stack.container.size.height = height
        guard stack.container.size.width > 0, height > 0, base.length > 0 else { return true }
        if laidOutScale != fontScale {
            stack.storage.setAttributedString(fontScale == 1 ? base : RichTextUtils.scaled(base, by: fontScale))
            laidOutScale = fontScale
        }
        stack.layoutManager.ensureLayout(for: stack.container)
        return NSMaxRange(stack.layoutManager.glyphRange(for: stack.container)) >= stack.layoutManager.numberOfGlyphs
    }

    /// The largest scale in `minimumShrinkScale...1` that fits, or the minimum when even that overflows.
    func largestFittingScale(height: CGFloat) -> (scale: CGFloat, fits: Bool) {
        if fits(fontScale: 1, height: height) { return (1, true) }
        let floor = TextFitMeasurer.minimumShrinkScale
        guard fits(fontScale: floor, height: height) else { return (floor, false) }
        var low = floor
        var high: CGFloat = 1
        for _ in 0..<Self.scaleSearchSteps {
            let mid = (low + high) / 2
            if fits(fontScale: mid, height: height) { low = mid } else { high = mid }
        }
        return (low, true)
    }

    /// The smallest height in `minHeight...maxHeight` at which the text fits at `fontScale`, or nil.
    func minimumFittingHeight(fontScale: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat? {
        guard fits(fontScale: fontScale, height: maxHeight) else { return nil }
        var low = minHeight
        var high = maxHeight
        for _ in 0..<Self.heightSearchSteps {
            let mid = (low + high) / 2
            if fits(fontScale: fontScale, height: mid) { high = mid } else { low = mid }
        }
        return high
    }
}
