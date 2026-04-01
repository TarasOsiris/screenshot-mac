import Foundation

struct LocaleDefinition: Codable, Identifiable, Equatable {
    var code: String
    var label: String
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code = "c", label = "l"
    }

    init(code: String, label: String) {
        self.code = code
        self.label = label
    }

    var flag: String { Self.flags[code] ?? "" }

    var flagLabel: String { flag.isEmpty ? label : "\(flag) \(label)" }

    private static let flags: [String: String] = [
        "en": "🇺🇸", "fr": "🇫🇷", "de": "🇩🇪", "es": "🇪🇸", "it": "🇮🇹",
        "pt": "🇧🇷", "nl": "🇳🇱", "ru": "🇷🇺", "ja": "🇯🇵", "ko": "🇰🇷",
        "zh": "🇨🇳", "ar": "🇸🇦", "hi": "🇮🇳", "tr": "🇹🇷", "pl": "🇵🇱",
        "sv": "🇸🇪", "da": "🇩🇰", "fi": "🇫🇮", "no": "🇳🇴", "uk": "🇺🇦",
        "th": "🇹🇭", "vi": "🇻🇳", "id": "🇮🇩", "ms": "🇲🇾", "cs": "🇨🇿",
        "el": "🇬🇷", "he": "🇮🇱", "hu": "🇭🇺", "ro": "🇷🇴", "sk": "🇸🇰",
    ]
}

struct ShapeLocaleOverride: Codable, Equatable {
    var offsetX: CGFloat?
    var offsetY: CGFloat?
    var offsetWidth: CGFloat?
    var offsetHeight: CGFloat?

    var text: String?
    var fontName: String?
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?
    var italic: Bool?
    var uppercase: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?

    var overrideImageFileName: String?

    enum CodingKeys: String, CodingKey {
        case offsetX = "ox", offsetY = "oy", offsetWidth = "ow", offsetHeight = "oh"
        case text = "txt", fontName = "fn", fontSize = "fs", fontWeight = "fw"
        case textAlign = "ta", italic = "it", uppercase = "uc"
        case letterSpacing = "ls", lineSpacing = "lns", lineHeightMultiple = "lhm"
        case overrideImageFileName = "oifn"
    }

    init(
        offsetX: CGFloat? = nil, offsetY: CGFloat? = nil,
        offsetWidth: CGFloat? = nil, offsetHeight: CGFloat? = nil,
        text: String? = nil, fontName: String? = nil,
        fontSize: CGFloat? = nil, fontWeight: Int? = nil,
        textAlign: TextAlign? = nil, italic: Bool? = nil,
        uppercase: Bool? = nil, letterSpacing: CGFloat? = nil,
        lineSpacing: CGFloat? = nil, lineHeightMultiple: CGFloat? = nil,
        overrideImageFileName: String? = nil
    ) {
        self.offsetX = offsetX; self.offsetY = offsetY
        self.offsetWidth = offsetWidth; self.offsetHeight = offsetHeight
        self.text = text; self.fontName = fontName
        self.fontSize = fontSize; self.fontWeight = fontWeight
        self.textAlign = textAlign; self.italic = italic
        self.uppercase = uppercase; self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing; self.lineHeightMultiple = lineHeightMultiple
        self.overrideImageFileName = overrideImageFileName
    }

    var isEmpty: Bool {
        offsetX == nil && offsetY == nil && offsetWidth == nil && offsetHeight == nil
            && text == nil && fontName == nil && fontSize == nil && fontWeight == nil
            && textAlign == nil && italic == nil && uppercase == nil
            && letterSpacing == nil && lineSpacing == nil && lineHeightMultiple == nil
            && overrideImageFileName == nil
    }
}

struct LocaleState: Codable, Equatable {
    var locales: [LocaleDefinition]
    var activeLocaleCode: String
    var overrides: [String: [String: ShapeLocaleOverride]]

    enum CodingKeys: String, CodingKey {
        case locales = "l", activeLocaleCode = "alc", overrides = "o"
    }

    init(locales: [LocaleDefinition], activeLocaleCode: String, overrides: [String: [String: ShapeLocaleOverride]]) {
        self.locales = locales
        self.activeLocaleCode = activeLocaleCode
        self.overrides = overrides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        locales = try c.decode([LocaleDefinition].self, forKey: .locales)
        activeLocaleCode = try c.decode(String.self, forKey: .activeLocaleCode)
        overrides = try c.decodeIfPresent([String: [String: ShapeLocaleOverride]].self, forKey: .overrides) ?? [:]
    }

    static let `default` = LocaleState(
        locales: [LocaleDefinition(code: "en", label: "English")],
        activeLocaleCode: "en",
        overrides: [:]
    )

    var isBaseLocale: Bool { activeLocaleCode == locales.first?.code }
    var baseLocaleCode: String { locales.first?.code ?? "en" }
    var activeLocaleLabel: String { locales.first { $0.code == activeLocaleCode }?.flagLabel ?? activeLocaleCode }

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
