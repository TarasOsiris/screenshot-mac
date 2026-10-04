import Foundation

extension CanvasShapeModel {
    /// The catalog key this text shape's string lives under: a shared key when linked, else its own id.
    nonisolated var textTranslationKey: String { translationKey ?? id.uuidString }

    var hasTranslatableText: Bool {
        type == .text && !(text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func extractTextStyle() -> TextStyle {
        TextStyle(
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            textAlign: textAlign,
            textVerticalAlign: textVerticalAlign,
            italic: italic,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineSpacing: lineSpacing,
            lineHeightMultiple: lineHeightMultiple,
            colorData: colorData,
            opacity: opacity
        )
    }

    mutating func applyTextStyle(_ style: TextStyle) {
        fontName = style.fontName
        fontSize = style.fontSize
        fontWeight = style.fontWeight
        textAlign = style.textAlign
        textVerticalAlign = style.textVerticalAlign
        italic = style.italic
        uppercase = style.uppercase
        letterSpacing = style.letterSpacing
        lineSpacing = style.lineSpacing
        lineHeightMultiple = style.lineHeightMultiple
        colorData = style.colorData
        opacity = style.opacity
        richText = nil
    }

    var hasRichText: Bool { richText != nil }
}
