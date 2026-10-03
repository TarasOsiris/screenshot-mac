import Foundation

/// One face of an imported font file — the only one for a static file, one per named instance of a
/// variable font or `.ttc`. Each is its own picker entry.
nonisolated struct CustomFont: Hashable {
    let fileName: String
    let familyName: String
    let styleName: String?
    let postScriptName: String?
    let isBold: Bool
    let isItalic: Bool
    let suggestedFontWeight: Int
    /// Full 100–900 CSS weight inferred from the style name; `suggestedFontWeight` buckets it to the
    /// picker's presets (300/400/500/700).
    let typographicWeight: Int

    init(
        fileName: String,
        familyName: String,
        styleName: String?,
        postScriptName: String?,
        isBold: Bool,
        isItalic: Bool
    ) {
        self.fileName = fileName
        self.familyName = familyName
        self.styleName = styleName
        self.postScriptName = postScriptName
        self.isBold = isBold
        self.isItalic = isItalic
        self.suggestedFontWeight = Self.deriveSuggestedFontWeight(styleName: styleName, isBold: isBold)
        self.typographicWeight = Self.deriveTypographicWeight(styleName: styleName, isBold: isBold)
    }

    /// User-facing name used in the font picker and stored in `shape.fontName`.
    var displayName: String {
        Self.displayName(familyName: familyName, styleName: styleName)
    }

    var exactNameForSelection: String? {
        postScriptName
    }

    /// Buckets the full typographic weight into the four presets the weight picker exposes,
    /// so both derivations stay defined by a single style-name parser.
    private static func deriveSuggestedFontWeight(styleName: String?, isBold: Bool) -> Int {
        switch deriveTypographicWeight(styleName: styleName, isBold: isBold) {
        case ...300: return 300
        case 400: return 400
        case 500: return 500
        default: return 700
        }
    }

    private static func deriveTypographicWeight(styleName: String?, isBold: Bool) -> Int {
        let normalized = styleName?.lowercased() ?? ""
        if normalized.contains("thin") || normalized.contains("hairline") { return 100 }
        if normalized.contains("ultralight") || normalized.contains("ultra light")
            || normalized.contains("extralight") || normalized.contains("extra light") { return 200 }
        if normalized.contains("semibold") || normalized.contains("semi bold")
            || normalized.contains("demibold") || normalized.contains("demi bold") { return 600 }
        if normalized.contains("extrabold") || normalized.contains("extra bold")
            || normalized.contains("ultrabold") || normalized.contains("ultra bold") { return 800 }
        if normalized.contains("black") || normalized.contains("heavy") { return 900 }
        if normalized.contains("light") { return 300 }
        if normalized.contains("medium") { return 500 }
        if isBold || normalized.contains("bold") { return 700 }
        return 400
    }

    func selectionResult() -> ImportedCustomFontSelection {
        ImportedCustomFontSelection(
            fontName: displayName,
            fontWeight: suggestedFontWeight,
            italic: isItalic
        )
    }

    static func displayName(familyName: String, styleName: String?) -> String {
        guard let styleName else { return familyName }
        let trimmed = styleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return familyName }
        return "\(familyName) \(trimmed)"
    }

    /// Tie-break between faces equally close to a request: the plainer style name wins, so "Bold"
    /// beats an optical-size "9pt Bold"; then a stable name order.
    static func plainerStyleFirst(_ lhs: CustomFont, _ rhs: CustomFont) -> Bool {
        let lhsLength = lhs.styleName?.count ?? 0
        let rhsLength = rhs.styleName?.count ?? 0
        if lhsLength != rhsLength { return lhsLength < rhsLength }
        return lhs.displayName != rhs.displayName ? lhs.displayName < rhs.displayName : lhs.fileName < rhs.fileName
    }

    static func isRegularStyle(_ style: String?) -> Bool {
        guard let style else { return false }
        let normalized = style.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty || normalized == "regular" || normalized == "normal" || normalized == "book" || normalized == "roman"
    }
}

struct ImportedCustomFontSelection: Equatable {
    let fontName: String
    let fontWeight: Int?
    let italic: Bool?
}

struct CustomFontControlState: Equatable {
    let effectiveWeight: Int
    let effectiveItalic: Bool
    let availableWeights: [Int]
    let showsWeightPicker: Bool
    let showsItalicToggle: Bool
}
