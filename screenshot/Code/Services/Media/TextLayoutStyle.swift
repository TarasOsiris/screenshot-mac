#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

/// Keeps fallback-glyph lines (Cyrillic in a Latin-only font) at declared-font height, and compresses
/// lineHeightMultiple < 1 by moving full-height fragments so ascenders aren't clipped. Attach with `install`.
final class LineMetricsLayoutDelegate: NSObject, NSLayoutManagerDelegate, NSTextStorageDelegate {
    nonisolated static let declaredFontKey = NSAttributedString.Key("xyz.tleskiv.screenshot.declaredFont")
    private static let metricsCacheLimit = 512
    /// Shared: every raster and fit step builds a fresh stack, so a per-instance cache never warms.
    private static var metricsCache: [NSFont: LineMetrics] = [:]

    var lineHeightMultiple: CGFloat = 1.0

    private struct LineMetrics {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0

        mutating func formMax(_ other: LineMetrics) {
            ascent = max(ascent, other.ascent)
            descent = max(descent, other.descent)
        }
    }

    /// The storage delegate is required too: font fixing overwrites `.font` with the fallback, so the
    /// declared font has to be recorded before it runs.
    func install(on layoutManager: NSLayoutManager, storage: NSTextStorage) {
        layoutManager.delegate = self
        storage.delegate = self
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        let string = textStorage.string as NSString
        textStorage.enumerateAttribute(.font, in: editedRange) { value, fontRange, _ in
            guard let font = value as? NSFont else { return }
            textStorage.enumerateAttribute(Self.declaredFontKey, in: fontRange) { declared, range, _ in
                let text = string.substring(with: range)
                // An attribute-only edit or a resize hands back the substituted font; keep what it replaced.
                if let declared = declared as? NSFont {
                    let sized = Self.resized(declared, to: font.pointSize)
                    if Self.isFallback(font, of: sized, for: text) {
                        if sized != declared { textStorage.addAttribute(Self.declaredFontKey, value: sized, range: range) }
                        return
                    }
                }
                // Tag only text the fixer will substitute, so storage equality checks stay unaffected.
                if Self.covers(font, text) {
                    if declared != nil { textStorage.removeAttribute(Self.declaredFontKey, range: range) }
                } else {
                    textStorage.addAttribute(Self.declaredFontKey, value: font, range: range)
                }
            }
        }
    }

    private static func covers(_ font: NSFont, _ text: String) -> Bool {
        var characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        return CTFontGetGlyphsForCharacters(font as CTFont, &characters, &glyphs, characters.count)
    }

    /// Puts substituted runs back in their declared font, so a fallback is never persisted as a choice.
    nonisolated static func restoringDeclaredFonts(_ attributed: NSAttributedString) -> NSAttributedString {
        let fullRange = NSRange(location: 0, length: attributed.length)
        var result: NSMutableAttributedString?
        attributed.enumerateAttribute(declaredFontKey, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let restored = result ?? NSMutableAttributedString(attributedString: attributed)
            result = restored
            attributed.enumerateAttributes(in: range) { attributes, runRange, _ in
                restored.setAttributes(restoringDeclaredFont(in: attributes), range: runRange)
            }
        }
        return result ?? attributed
    }

    /// One run's attributes with its fallback font swapped back for the declared one, at the run's size.
    nonisolated static func restoringDeclaredFont(in attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attributes = attributes
        guard let declared = attributes.removeValue(forKey: declaredFontKey) as? NSFont else { return attributes }
        attributes[.font] = resized(declared, to: (attributes[.font] as? NSFont)?.pointSize ?? declared.pointSize)
        return attributes
    }

    private nonisolated static func resized(_ font: NSFont, to size: CGFloat) -> NSFont {
        font.pointSize == size ? font : font.withSize(size)
    }

    /// Mirrors TextKit's own fallback pick (`CTFontCreateForString`), so this is what would drift if Apple changes it.
    private static func isFallback(_ font: NSFont, of declared: NSFont, for text: String) -> Bool {
        guard font != declared, !text.isEmpty else { return false }
        let fallback = CTFontCreateForString(declared as CTFont, text as CFString, CFRange(location: 0, length: (text as NSString).length))
        return CTFontCopyPostScriptName(fallback) as String == font.fontName
            && CTFontGetSize(fallback) == font.pointSize
    }

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        let raised = raiseToDeclaredMetrics(
            layoutManager,
            lineFragmentRect: lineFragmentRect,
            lineFragmentUsedRect: lineFragmentUsedRect,
            baselineOffset: baselineOffset,
            glyphRange: glyphRange
        )
        guard lineHeightMultiple < 1.0, glyphRange.location > 0 else { return raised }

        // From the fragment above, not a running total: an edit re-lays out from the edited line only.
        let previous = layoutManager.lineFragmentRect(
            forGlyphAt: glyphRange.location - 1,
            effectiveRange: nil,
            withoutAdditionalLayout: true
        )
        guard previous.height > 0 else { return raised }

        let delta = previous.minY + previous.height * lineHeightMultiple - lineFragmentRect.pointee.origin.y
        lineFragmentRect.pointee.origin.y += delta
        lineFragmentUsedRect.pointee.origin.y += delta
        return true
    }

    private func raiseToDeclaredMetrics(
        _ layoutManager: NSLayoutManager,
        lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        glyphRange: NSRange
    ) -> Bool {
        guard let storage = layoutManager.textStorage, lineFragmentRect.pointee.height > 0 else { return false }
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard characterRange.length > 0, NSMaxRange(characterRange) <= storage.length else { return false }

        var hasSubstitution = false
        storage.enumerateAttribute(Self.declaredFontKey, in: characterRange) { value, _, stop in
            if value != nil { hasSubstitution = true; stop.pointee = true }
        }
        guard hasSubstitution else { return false }

        var present = LineMetrics()
        var declared = LineMetrics()
        var measurable = true
        storage.enumerateAttributes(in: characterRange) { attributes, _, stop in
            guard let font = attributes[.font] as? NSFont else { return }
            guard let fontMetrics = Self.metrics(for: font) else { measurable = false; stop.pointee = true; return }
            present.formMax(fontMetrics)
            if let declaredFont = attributes[Self.declaredFontKey] as? NSFont, let declaredMetrics = Self.metrics(for: declaredFont) {
                declared.formMax(declaredMetrics)
            } else {
                declared.formMax(fontMetrics)
            }
        }
        // Raise by the font difference, not to a target height: TextKit already folded paragraph
        // spacing and `.baselineOffset` into the fragment.
        guard measurable else { return false }
        let ascentRaise = max(0, declared.ascent - present.ascent)
        let descentRaise = max(0, declared.descent - present.descent)
        guard ascentRaise + descentRaise > 0.01 else { return false }

        // TextKit scales the natural line by the paragraph's multiple and puts the extra above the baseline.
        let style = storage.attribute(.paragraphStyle, at: characterRange.location, effectiveRange: nil) as? NSParagraphStyle
        let styledMultiple = style?.lineHeightMultiple ?? 0
        let multiple = styledMultiple > 0 ? styledMultiple : 1
        let heightRaise = (ascentRaise + descentRaise) * multiple

        lineFragmentRect.pointee.size.height += heightRaise
        lineFragmentUsedRect.pointee.size.height += heightRaise
        baselineOffset.pointee += heightRaise - descentRaise
        return true
    }

    /// Measured by TextKit itself: its line rounding doesn't follow from ascender/descender alone.
    private static func metrics(for font: NSFont) -> LineMetrics? {
        if let cached = metricsCache[font] { return cached }
        guard let probe = [" ", "x", "H", "0"].first(where: { covers(font, $0) }) else { return nil }

        let storage = NSTextStorage(string: probe, attributes: [.font: font])
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        guard layoutManager.numberOfGlyphs > 0 else { return nil }

        let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let baseline = layoutManager.location(forGlyphAt: 0).y
        let metrics = LineMetrics(ascent: baseline, descent: rect.height - baseline)
        if metricsCache.count >= metricsCacheLimit { metricsCache.removeAll(keepingCapacity: true) }
        metricsCache[font] = metrics
        return metrics
    }
}

/// A glyph outline drawn under the fill; `width` is the visible band outside the glyphs, in model points.
struct TextStroke: Equatable {
    var color: NSColor
    var width: CGFloat

    /// Whole points of margin the raster needs so the band isn't clipped at the box edge.
    var rasterPadding: CGFloat { ceil(max(0, width)) }

    static func paddedSize(_ size: CGSize, for stroke: TextStroke?) -> CGSize {
        let pad = stroke?.rasterPadding ?? 0
        return CGSize(width: size.width + 2 * pad, height: size.height + 2 * pad)
    }
}

/// The TextKit stack every text raster and fit measurement lays out with, so a fit check makes
/// exactly the line breaks the raster it predicts will make.
final class TextLayoutStack {
    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let container: NSTextContainer
    /// Held here: `NSLayoutManager.delegate` is weak.
    private let lineMetricsDelegate = LineMetricsLayoutDelegate()

    var lineHeightMultiple: CGFloat {
        get { lineMetricsDelegate.lineHeightMultiple }
        set { lineMetricsDelegate.lineHeightMultiple = newValue }
    }

    init(containerSize: CGSize = .zero, lineHeightMultiple: CGFloat? = nil) {
        container = NSTextContainer(size: containerSize)
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        lineMetricsDelegate.lineHeightMultiple = lineHeightMultiple ?? 1.0
        lineMetricsDelegate.install(on: layoutManager, storage: storage)
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
    }

    /// Highlights, then the outline, then the glyph fill on top.
    func draw(range: NSRange, at origin: CGPoint, stroke: TextStroke?) {
        layoutManager.drawBackground(forGlyphRange: range, at: origin)
        if let stroke {
            TextLayoutStyle.applyStroke(to: storage, color: stroke.color, width: stroke.width)
            layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
            TextLayoutStyle.removeStroke(from: storage)
        }
        layoutManager.drawGlyphs(forGlyphRange: range, at: origin)
    }
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
            // For < 1.0, LineMetricsLayoutDelegate keeps full-height line fragments,
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
            // line fragment rects and causes glyph clipping. LineMetricsLayoutDelegate
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
            let baselineOffset = baselineOffset(
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing,
                font: font
            )
            if baselineOffset != 0 {
                attributes[.baselineOffset] = baselineOffset
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

    static func scaledFont(_ font: NSFont, by factor: CGFloat) -> NSFont {
        factor == 1 ? font : font.withSize(font.pointSize * factor)
    }

    // MARK: - Cache-key tokens

    /// Lossless scalar tokens prevent fractional model-space dimensions and subtly different
    /// styling values from aliasing to one cache entry. `String(format:)` rounding is unsafe here:
    /// even two bounds that round to the same point can require different backing-pixel sizes.
    static func scalarToken(_ value: CGFloat) -> String {
        String(Double(value).bitPattern, radix: 16)
    }

    /// Weight is not recoverable from `fontName` alone for a variable font resolved to an instance,
    /// so it goes in the key explicitly — two weights of one family must not collide.
    static func fontWeightToken(_ font: NSFont) -> String {
        #if os(macOS)
        let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        #else
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        #endif
        return (traits?[.weight] as? CGFloat).map(scalarToken) ?? "-"
    }

    static func colorToken(_ color: NSColor) -> String {
        let cgColor = color.cgColor
        let colorSpace = String(describing: cgColor.colorSpace?.name)
        let components = (cgColor.components ?? []).map(scalarToken).joined(separator: ",")
        return "\(colorSpace),\(cgColor.numberOfComponents),\(components)"
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
