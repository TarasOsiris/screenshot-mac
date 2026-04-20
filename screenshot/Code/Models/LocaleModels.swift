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

    var flag: String { Self.flagIndex[code] ?? "" }

    var flagLabel: String { flag.isEmpty ? label : "\(flag) \(label)" }

    static let catalog: [(code: String, label: String, flag: String)] = [
        ("en", "English",     "🇺🇸"), ("fr", "French",      "🇫🇷"), ("de", "German",      "🇩🇪"),
        ("es", "Spanish",     "🇪🇸"), ("it", "Italian",     "🇮🇹"), ("pt", "Portuguese",  "🇧🇷"),
        ("nl", "Dutch",       "🇳🇱"), ("ru", "Russian",     "🇷🇺"), ("ja", "Japanese",    "🇯🇵"),
        ("ko", "Korean",      "🇰🇷"), ("zh", "Chinese",     "🇨🇳"), ("ar", "Arabic",      "🇸🇦"),
        ("hi", "Hindi",       "🇮🇳"), ("tr", "Turkish",     "🇹🇷"), ("pl", "Polish",      "🇵🇱"),
        ("sv", "Swedish",     "🇸🇪"), ("da", "Danish",      "🇩🇰"), ("fi", "Finnish",     "🇫🇮"),
        ("no", "Norwegian",   "🇳🇴"), ("uk", "Ukrainian",   "🇺🇦"), ("th", "Thai",        "🇹🇭"),
        ("vi", "Vietnamese",  "🇻🇳"), ("id", "Indonesian",  "🇮🇩"), ("ms", "Malay",       "🇲🇾"),
        ("cs", "Czech",       "🇨🇿"), ("el", "Greek",       "🇬🇷"), ("he", "Hebrew",      "🇮🇱"),
        ("hu", "Hungarian",   "🇭🇺"), ("ro", "Romanian",    "🇷🇴"), ("sk", "Slovak",      "🇸🇰"),
        ("bg", "Bulgarian",   "🇧🇬"), ("hr", "Croatian",    "🇭🇷"), ("sr", "Serbian",     "🇷🇸"),
        ("ca", "Catalan",     "🇪🇸"), ("fa", "Persian",     "🇮🇷"), ("bn", "Bengali",     "🇧🇩"),
        ("fil","Filipino",    "🇵🇭"), ("lt", "Lithuanian",  "🇱🇹"), ("lv", "Latvian",     "🇱🇻"),
        ("et", "Estonian",    "🇪🇪"), ("sl", "Slovenian",   "🇸🇮"), ("kk", "Kazakh",      "🇰🇿"),
        ("uz", "Uzbek",       "🇺🇿"), ("ta", "Tamil",       "🇮🇳"), ("te", "Telugu",      "🇮🇳"),
        ("mr", "Marathi",     "🇮🇳"), ("sw", "Swahili",     "🇰🇪"), ("af", "Afrikaans",   "🇿🇦"),
        ("gu", "Gujarati",    "🇮🇳"), ("kn", "Kannada",     "🇮🇳"), ("ml", "Malayalam",   "🇮🇳"),
        ("pa", "Punjabi",     "🇮🇳"), ("my", "Burmese",     "🇲🇲"), ("km", "Khmer",       "🇰🇭"),
        ("ne", "Nepali",      "🇳🇵"), ("si", "Sinhala",     "🇱🇰"), ("mn", "Mongolian",   "🇲🇳"),
        ("az", "Azerbaijani", "🇦🇿"), ("ka", "Georgian",    "🇬🇪"), ("hy", "Armenian",    "🇦🇲"),
        ("be", "Belarusian",  "🇧🇾"), ("sq", "Albanian",    "🇦🇱"), ("mk", "Macedonian",  "🇲🇰"),
        ("bs", "Bosnian",     "🇧🇦"), ("is", "Icelandic",   "🇮🇸"), ("mt", "Maltese",     "🇲🇹"),
        ("ga", "Irish",       "🇮🇪"), ("cy", "Welsh",       "🏴󠁧󠁢󠁷󠁬󠁳󠁿"), ("eu", "Basque",      "🇪🇸"),
        ("gl", "Galician",    "🇪🇸"),
    ]

    private static let flagIndex: [String: String] =
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.code, $0.flag) })
}

struct ShapeLocaleOverride: Codable, Equatable {
    var offsetX: CGFloat?
    var offsetY: CGFloat?
    var offsetWidth: CGFloat?
    var offsetHeight: CGFloat?

    var text: String?
    var richText: String?
    var clearsRichText: Bool?
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
        case text = "txt", richText = "rt", clearsRichText = "crt", fontName = "fn", fontSize = "fs", fontWeight = "fw"
        case textAlign = "ta", italic = "it", uppercase = "uc"
        case letterSpacing = "ls", lineSpacing = "lns", lineHeightMultiple = "lhm"
        case overrideImageFileName = "oifn"
    }

    init(
        offsetX: CGFloat? = nil, offsetY: CGFloat? = nil,
        offsetWidth: CGFloat? = nil, offsetHeight: CGFloat? = nil,
        text: String? = nil, richText: String? = nil, clearsRichText: Bool? = nil, fontName: String? = nil,
        fontSize: CGFloat? = nil, fontWeight: Int? = nil,
        textAlign: TextAlign? = nil, italic: Bool? = nil,
        uppercase: Bool? = nil, letterSpacing: CGFloat? = nil,
        lineSpacing: CGFloat? = nil, lineHeightMultiple: CGFloat? = nil,
        overrideImageFileName: String? = nil
    ) {
        self.offsetX = offsetX; self.offsetY = offsetY
        self.offsetWidth = offsetWidth; self.offsetHeight = offsetHeight
        self.text = text; self.richText = richText; self.clearsRichText = clearsRichText; self.fontName = fontName
        self.fontSize = fontSize; self.fontWeight = fontWeight
        self.textAlign = textAlign; self.italic = italic
        self.uppercase = uppercase; self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing; self.lineHeightMultiple = lineHeightMultiple
        self.overrideImageFileName = overrideImageFileName
    }

    var isEmpty: Bool {
        offsetX == nil && offsetY == nil && offsetWidth == nil && offsetHeight == nil
            && text == nil && richText == nil && clearsRichText != true && fontName == nil && fontSize == nil && fontWeight == nil
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
    static let all: [LocaleDefinition] = LocaleDefinition.catalog.map {
        .init(code: $0.code, label: $0.label)
    }
}
