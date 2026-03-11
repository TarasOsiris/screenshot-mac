import Foundation

struct LocaleDefinition: Codable, Identifiable, Equatable {
    var code: String
    var label: String
    var id: String { code }
}

struct ShapeLocaleOverride: Codable, Equatable {
    // Position & size (all shape types)
    var x: CGFloat?
    var y: CGFloat?
    var width: CGFloat?
    var height: CGFloat?

    // Text properties (text shapes only)
    var text: String?
    var fontName: String?
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?
    var italic: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?

    // Display image override (device screenshot or standalone image)
    var overrideImageFileName: String?

    var isEmpty: Bool {
        x == nil && y == nil && width == nil && height == nil
            && text == nil && fontName == nil && fontSize == nil && fontWeight == nil
            && textAlign == nil && italic == nil && letterSpacing == nil && lineSpacing == nil
            && overrideImageFileName == nil
    }
}

struct LocaleState: Codable, Equatable {
    var locales: [LocaleDefinition]
    var activeLocaleCode: String
    var overrides: [String: [String: ShapeLocaleOverride]]  // localeCode → shapeId → override

    static let `default` = LocaleState(
        locales: [LocaleDefinition(code: "en", label: "English")],
        activeLocaleCode: "en",
        overrides: [:]
    )

    var isBaseLocale: Bool { activeLocaleCode == locales.first?.code }
    var baseLocaleCode: String { locales.first?.code ?? "en" }
    var activeLocaleLabel: String { locales.first { $0.code == activeLocaleCode }?.label ?? activeLocaleCode }

    /// Check if a shape has any override for the active locale.
    func hasOverride(shapeId: UUID) -> Bool {
        override(forCode: activeLocaleCode, shapeId: shapeId) != nil
    }

    /// Get the override for a shape in a specific locale.
    func override(forCode code: String, shapeId: UUID) -> ShapeLocaleOverride? {
        overrides[code]?[shapeId.uuidString]
    }

}

enum LocalePresets {
    static let all: [LocaleDefinition] = [
        .init(code: "en", label: "English"),
        .init(code: "fr", label: "French"),
        .init(code: "de", label: "German"),
        .init(code: "es", label: "Spanish"),
        .init(code: "it", label: "Italian"),
        .init(code: "pt", label: "Portuguese"),
        .init(code: "nl", label: "Dutch"),
        .init(code: "ru", label: "Russian"),
        .init(code: "ja", label: "Japanese"),
        .init(code: "ko", label: "Korean"),
        .init(code: "zh", label: "Chinese"),
        .init(code: "ar", label: "Arabic"),
        .init(code: "hi", label: "Hindi"),
        .init(code: "tr", label: "Turkish"),
        .init(code: "pl", label: "Polish"),
        .init(code: "sv", label: "Swedish"),
        .init(code: "da", label: "Danish"),
        .init(code: "fi", label: "Finnish"),
        .init(code: "no", label: "Norwegian"),
        .init(code: "uk", label: "Ukrainian"),
        .init(code: "th", label: "Thai"),
        .init(code: "vi", label: "Vietnamese"),
        .init(code: "id", label: "Indonesian"),
        .init(code: "ms", label: "Malay"),
        .init(code: "cs", label: "Czech"),
        .init(code: "el", label: "Greek"),
        .init(code: "he", label: "Hebrew"),
        .init(code: "hu", label: "Hungarian"),
        .init(code: "ro", label: "Romanian"),
        .init(code: "sk", label: "Slovak"),
    ]
}
