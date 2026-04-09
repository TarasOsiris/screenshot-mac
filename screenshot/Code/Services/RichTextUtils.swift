import AppKit
import SwiftUI

enum RichTextUtils {
    enum ShapeStyleProperty {
        case color
        case fontName
        case fontSize
        case fontWeight
        case italic
        case alignment
        case letterSpacing
        case lineHeight
    }

    /// Encode an NSAttributedString to a Base64-encoded RTF string for persistence.
    static func encode(_ attributedString: NSAttributedString) -> String? {
        let range = NSRange(location: 0, length: attributedString.length)
        guard let rtfData = try? attributedString.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) else { return nil }
        return rtfData.base64EncodedString()
    }

    /// Decode a Base64-encoded RTF string back to an NSAttributedString.
    static func decode(_ base64RTF: String) -> NSAttributedString? {
        guard let data = Data(base64Encoded: base64RTF) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
    }

    /// Build a display-ready NSAttributedString from a shape's text properties.
    /// If richText is present, decodes it; otherwise builds uniform attributed string from plain text.
    static func buildAttributedString(
        richText: String?,
        plainText: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        uppercase: Bool
    ) -> NSAttributedString {
        let displayText = uppercase ? plainText.uppercased() : plainText

        if let richText, let decoded = decode(richText) {
            let decodedText = uppercase ? decoded.string.uppercased() : decoded.string
            guard decodedText == displayText else {
                return retargetAttributedString(
                    decoded,
                    to: displayText,
                    fallbackFont: font,
                    fallbackColor: color,
                    alignment: alignment,
                    letterSpacing: letterSpacing,
                    lineHeightMultiple: lineHeightMultiple,
                    legacyLineSpacing: legacyLineSpacing
                )
            }
            let merged = mergeParagraphStyle(
                into: decoded,
                alignment: alignment,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing
            )
            return uppercase ? uppercased(merged) : merged
        }

        // Fallback: uniform style from shape-level properties
        let attributes = TextLayoutStyle.textAttributes(
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing
        )
        return NSAttributedString(string: displayText, attributes: attributes)
    }

    /// Reuse the rich text's current typing style when its stored string no longer
    /// matches the model text. Per-range formatting cannot be mapped reliably across
    /// arbitrary edits/translations, but displaying stale characters is worse.
    private static func retargetAttributedString(
        _ attributedString: NSAttributedString,
        to displayText: String,
        fallbackFont: NSFont,
        fallbackColor: NSColor,
        alignment: NSTextAlignment,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?
    ) -> NSAttributedString {
        var attributes = TextLayoutStyle.textAttributes(
            font: fallbackFont,
            color: fallbackColor,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing
        )

        if attributedString.length > 0 {
            attributedString.enumerateAttributes(
                in: NSRange(location: 0, length: attributedString.length),
                options: []
            ) { attrs, _, stop in
                for (key, value) in attrs where key != .paragraphStyle && key != .kern {
                    attributes[key] = value
                }
                stop.pointee = true
            }
        }

        return NSAttributedString(string: displayText, attributes: attributes)
    }

    /// Extract plain text from a Base64-encoded RTF string.
    static func plainText(from base64RTF: String) -> String? {
        decode(base64RTF)?.string
    }

    /// Uppercase an attributed string while preserving per-range attributes.
    static func uppercased(_ attributedString: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: fullRange) { attrs, range, _ in
            let substring = (attributedString.string as NSString).substring(with: range)
            result.append(NSAttributedString(string: substring.uppercased(), attributes: attrs))
        }
        return result
    }

    static func syncShapeStyle(in shape: inout CanvasShapeModel, property: ShapeStyleProperty) {
        guard let richText = shape.richText,
              let decoded = decode(richText)?.mutableCopy() as? NSMutableAttributedString
        else { return }

        let fullRange = NSRange(location: 0, length: decoded.length)
        guard fullRange.length > 0 else {
            shape.richText = nil
            return
        }

        switch property {
        case .color:
            decoded.addAttribute(.foregroundColor, value: NSColor(shape.color), range: fullRange)

        case .fontName:
            rewriteFonts(in: decoded, range: fullRange) { font in
                let size = font?.pointSize ?? shape.fontSize ?? CanvasShapeModel.defaultFontSize
                let italic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? (shape.italic ?? false)
                let managerWeight = font.map(fontManagerWeight(of:)) ?? fontManagerWeight(for: shape.fontWeight ?? 400)
                return makeFont(
                    familyName: normalizedFontFamilyName(shape.fontName),
                    size: size,
                    managerWeight: managerWeight,
                    italic: italic
                )
            }

        case .fontSize:
            let size = shape.fontSize ?? CanvasShapeModel.defaultFontSize
            rewriteFonts(in: decoded, range: fullRange) { font in
                let familyName = font.flatMap { preferredFamilyName(for: $0) }
                let italic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? (shape.italic ?? false)
                let managerWeight = font.map(fontManagerWeight(of:)) ?? fontManagerWeight(for: shape.fontWeight ?? 400)
                return makeFont(
                    familyName: familyName,
                    size: size,
                    managerWeight: managerWeight,
                    italic: italic
                )
            }

        case .fontWeight:
            let managerWeight = fontManagerWeight(for: shape.fontWeight ?? 400)
            rewriteFonts(in: decoded, range: fullRange) { font in
                let familyName = font.flatMap { preferredFamilyName(for: $0) } ?? normalizedFontFamilyName(shape.fontName)
                let size = font?.pointSize ?? shape.fontSize ?? CanvasShapeModel.defaultFontSize
                let italic = font?.fontDescriptor.symbolicTraits.contains(.italic) ?? (shape.italic ?? false)
                return makeFont(
                    familyName: familyName,
                    size: size,
                    managerWeight: managerWeight,
                    italic: italic
                )
            }

        case .italic:
            let italic = shape.italic ?? false
            rewriteFonts(in: decoded, range: fullRange) { font in
                let familyName = font.flatMap { preferredFamilyName(for: $0) } ?? normalizedFontFamilyName(shape.fontName)
                let size = font?.pointSize ?? shape.fontSize ?? CanvasShapeModel.defaultFontSize
                let managerWeight = font.map(fontManagerWeight(of:)) ?? fontManagerWeight(for: shape.fontWeight ?? 400)
                return makeFont(
                    familyName: familyName,
                    size: size,
                    managerWeight: managerWeight,
                    italic: italic
                )
            }

        case .alignment, .letterSpacing, .lineHeight:
            let merged = mergeParagraphStyle(
                into: decoded,
                alignment: shape.textAlign.nsTextAlignment,
                letterSpacing: shape.letterSpacing,
                lineHeightMultiple: shape.lineHeightMultiple,
                legacyLineSpacing: shape.lineSpacing
            )
            decoded.setAttributedString(merged)
        }

        shape.richText = encode(decoded)
    }

    private static func mergeParagraphStyle(
        into attributedString: NSAttributedString,
        alignment: NSTextAlignment,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?
    ) -> NSAttributedString {
        let mutable = attributedString.mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributedString)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return mutable }

        mutable.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let paragraph = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            paragraph.alignment = alignment

            let baseFont = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                ?? NSFont.systemFont(ofSize: CanvasShapeModel.defaultFontSize)
            let defaultStyle = TextLayoutStyle.textAttributes(
                font: baseFont,
                color: .labelColor,
                alignment: alignment,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing
            )
            if let defaultParagraph = defaultStyle[.paragraphStyle] as? NSParagraphStyle {
                paragraph.minimumLineHeight = defaultParagraph.minimumLineHeight
                paragraph.maximumLineHeight = defaultParagraph.maximumLineHeight
                paragraph.lineSpacing = defaultParagraph.lineSpacing
                paragraph.paragraphSpacing = defaultParagraph.paragraphSpacing
                paragraph.paragraphSpacingBefore = defaultParagraph.paragraphSpacingBefore
            }
            mutable.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }

        if let letterSpacing {
            mutable.addAttribute(.kern, value: letterSpacing, range: fullRange)
        } else {
            mutable.removeAttribute(.kern, range: fullRange)
        }

        return mutable
    }

    private static func rewriteFonts(
        in attributedString: NSMutableAttributedString,
        range: NSRange,
        transform: (NSFont?) -> NSFont
    ) {
        attributedString.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            let font = value as? NSFont
            attributedString.addAttribute(.font, value: transform(font), range: attrRange)
        }
    }

    private static func normalizedFontFamilyName(_ fontName: String?) -> String? {
        guard let fontName, !fontName.isEmpty else { return nil }
        return fontName
    }

    private static func preferredFamilyName(for font: NSFont) -> String? {
        let familyName = font.familyName ?? font.fontDescriptor.object(forKey: .family) as? String
        return normalizedFontFamilyName(familyName)
    }

    private static func fontManagerWeight(of font: NSFont) -> Int {
        NSFontManager.shared.weight(of: font)
    }

    private static func fontManagerWeight(for cssWeight: Int) -> Int {
        switch cssWeight {
        case ...299: 3
        case 300...399: 4
        case 400...499: 5
        case 500...599: 6
        case 600...699: 8
        case 700...799: 9
        default: 11
        }
    }

    private static func nsFontWeight(for managerWeight: Int) -> NSFont.Weight {
        switch managerWeight {
        case ..<4: .thin
        case 4: .light
        case 5: .regular
        case 6: .medium
        case 7...8: .semibold
        case 9...10: .bold
        default: .heavy
        }
    }

    private static func makeFont(
        familyName: String?,
        size: CGFloat,
        managerWeight: Int,
        italic: Bool
    ) -> NSFont {
        let fontManager = NSFontManager.shared
        let traits: NSFontTraitMask = italic ? .italicFontMask : []

        if let familyName {
            if let font = fontManager.font(withFamily: familyName, traits: traits, weight: managerWeight, size: size) {
                return font
            }
            if let baseFont = fontManager.font(withFamily: familyName, traits: [], weight: managerWeight, size: size) {
                return italic ? fontManager.convert(baseFont, toHaveTrait: .italicFontMask) : baseFont
            }
            let fallback = CTFontCreateWithName(familyName as CFString, size, nil) as NSFont
            return italic ? fontManager.convert(fallback, toHaveTrait: .italicFontMask) : fallback
        }

        let system = NSFont.systemFont(ofSize: size, weight: nsFontWeight(for: managerWeight))
        return italic ? fontManager.convert(system, toHaveTrait: .italicFontMask) : system
    }
}
