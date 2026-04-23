import AppKit
import CoreText
import Foundation

/// Metadata for a user-imported font file. One family can have multiple files (Regular,
/// Italic, Bold, …); each is shown as its own picker entry.
struct CustomFont: Hashable {
    let fileName: String
    let familyName: String
    let styleName: String?
    let postScriptName: String?
    let isBold: Bool
    let isItalic: Bool
    let suggestedFontWeight: Int

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
    }

    /// User-facing name used in the font picker and stored in `shape.fontName`.
    var displayName: String {
        Self.displayName(familyName: familyName, styleName: styleName)
    }

    var exactNameForSelection: String? {
        postScriptName
    }

    private static func deriveSuggestedFontWeight(styleName: String?, isBold: Bool) -> Int {
        let normalized = styleName?.lowercased() ?? ""
        if normalized.contains("thin")
            || normalized.contains("hairline")
            || normalized.contains("ultralight")
            || normalized.contains("ultra light")
            || normalized.contains("extralight")
            || normalized.contains("extra light")
            || normalized.contains("light") {
            return 300
        }
        if normalized.contains("medium") {
            return 500
        }
        if isBold
            || normalized.contains("semibold")
            || normalized.contains("semi bold")
            || normalized.contains("demibold")
            || normalized.contains("demi bold")
            || normalized.contains("extrabold")
            || normalized.contains("extra bold")
            || normalized.contains("bold")
            || normalized.contains("black")
            || normalized.contains("heavy") {
            return 700
        }
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

    fileprivate static func isRegularStyle(_ style: String?) -> Bool {
        guard let style else { return false }
        let normalized = style.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty || normalized == "regular" || normalized == "normal" || normalized == "book" || normalized == "roman"
    }

    /// Reads a font file's descriptor to produce the metadata needed to register it. Used
    /// both by the import path (CTFontManagerRegisterFontsForURL has already been invoked
    /// by the caller) and by tooling that just needs to identify a font without registering.
    static func parseMetadata(at url: URL) -> CustomFont? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        let styleName = CTFontDescriptorCopyAttribute(first, kCTFontStyleNameAttribute) as? String
        let traits = (CTFontDescriptorCopyAttribute(first, kCTFontTraitsAttribute) as? [String: Any]) ?? [:]
        let symbolic = (traits[kCTFontSymbolicTrait as String] as? UInt32).map { CTFontSymbolicTraits(rawValue: $0) } ?? []

        return CustomFont(
            fileName: url.lastPathComponent,
            familyName: familyName,
            styleName: styleName,
            postScriptName: CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String,
            isBold: symbolic.contains(.boldTrait),
            isItalic: symbolic.contains(.italicTrait)
        )
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

/// Process-wide lookup so rendering code can resolve a `shape.fontName` (which may be a
/// custom font's display name) back to family + traits without having to thread the full
/// custom-font dictionary through every call site. AppState keeps this in sync via
/// `refreshAvailableFontFamilies()`.
enum CustomFontRegistry {
    struct ResolvedFont: Equatable {
        let family: String
        let exactName: String?
        let italic: Bool
    }

    private static var byDisplayName: [String: CustomFont] = [:]
    private static var byFamily: [String: [CustomFont]] = [:]

    static func update(with fonts: [String: CustomFont]) {
        var map: [String: CustomFont] = [:]
        var familyMap: [String: [CustomFont]] = [:]
        for font in fonts.values {
            map[font.displayName] = font
            familyMap[font.familyName, default: []].append(font)
        }
        byDisplayName = map
        byFamily = familyMap
    }

    static func font(forDisplayName name: String) -> CustomFont? {
        byDisplayName[name]
    }

    static func controlState(for shape: CanvasShapeModel) -> CustomFontControlState? {
        controlState(name: shape.fontName, fontWeight: shape.fontWeight, italic: shape.italic)
    }

    static func controlState(name: String?, fontWeight: Int?, italic: Bool?) -> CustomFontControlState? {
        guard let name, !name.isEmpty else { return nil }
        let resolved = resolve(name)
        guard let variants = byFamily[resolved.family], !variants.isEmpty else { return nil }

        let requestedWeight = normalizedPresetWeight(fontWeight ?? 400)
        let requestedItalic = italic ?? false
        let selectedVariant = byDisplayName[name] ?? bestVariant(in: variants, weight: requestedWeight, italic: requestedItalic)
        let effectiveWeight = selectedVariant?.suggestedFontWeight ?? requestedWeight
        let effectiveItalic = selectedVariant?.isItalic ?? requestedItalic

        let sameItalicVariants = variants.filter { $0.isItalic == effectiveItalic }
        let weightSource = sameItalicVariants.isEmpty ? variants : sameItalicVariants
        let availableWeights = presetWeights(in: weightSource)

        return CustomFontControlState(
            effectiveWeight: effectiveWeight,
            effectiveItalic: effectiveItalic,
            availableWeights: availableWeights,
            showsWeightPicker: Set(weightSource.map(\.suggestedFontWeight)).count > 1,
            showsItalicToggle: exactVariant(in: variants, weight: effectiveWeight, italic: !effectiveItalic) != nil
        )
    }

    /// Returns an exact imported face for the requested traits. For legacy family-only
    /// selections we still best-match into one of the imported variants.
    static func selection(name: String?, fontWeight: Int?, italic: Bool?) -> ImportedCustomFontSelection? {
        guard let name, !name.isEmpty else { return nil }
        let resolved = resolve(name)
        guard let variants = byFamily[resolved.family], !variants.isEmpty else { return nil }

        let requestedWeight = normalizedPresetWeight(fontWeight ?? 400)
        let requestedItalic = italic ?? false

        if let exact = exactVariant(in: variants, weight: requestedWeight, italic: requestedItalic) {
            return exact.selectionResult()
        }

        guard byDisplayName[name] == nil,
              let best = bestVariant(in: variants, weight: requestedWeight, italic: requestedItalic) else {
            return nil
        }
        return best.selectionResult()
    }

    static func preferredSelection(for familyName: String, in fonts: [String: CustomFont]) -> ImportedCustomFontSelection? {
        let variants = fonts.values.filter { $0.familyName == familyName }
        return preferredVariant(in: variants)?.selectionResult()
    }

    /// Resolves a `shape.fontName` to the underlying family name plus any italic trait
    /// inherent to the chosen variant. Falls back to treating the name as a system family.
    static func resolve(_ name: String) -> ResolvedFont {
        if let custom = byDisplayName[name] {
            return ResolvedFont(
                family: custom.familyName,
                exactName: custom.exactNameForSelection,
                italic: custom.isItalic
            )
        }
        return ResolvedFont(family: name, exactName: nil, italic: false)
    }

    /// Resolves a font display name to an NSFont. Picks the exact PostScript variant when
    /// known (so "Playfair Display Italic" renders that exact face); otherwise walks the
    /// NSFontManager fallback ladder against the family.
    static func resolveNSFont(name: String, size: CGFloat, managerWeight: Int, italic: Bool) -> NSFont {
        let resolved = resolve(name)
        let effectiveItalic = italic || resolved.italic
        let traits: NSFontTraitMask = resolved.italic ? .italicFontMask : []
        let fm = NSFontManager.shared

        let baseFont: NSFont
        if let exactName = resolved.exactName, let font = NSFont(name: exactName, size: size) {
            baseFont = font
        } else if let font = fm.font(withFamily: resolved.family, traits: traits, weight: managerWeight, size: size) {
            baseFont = font
        } else if let font = fm.font(withFamily: resolved.family, traits: traits, weight: 5, size: size) {
            // Synthetic bold for families that don't expose an explicit bold variant.
            baseFont = managerWeight >= 9 ? fm.convert(font, toHaveTrait: .boldFontMask) : font
        } else if let font = fm.font(withFamily: resolved.family, traits: [], weight: managerWeight, size: size) {
            baseFont = font
        } else {
            baseFont = CTFontCreateWithName(resolved.family as CFString, size, nil) as NSFont
        }
        return effectiveItalic ? fm.convert(baseFont, toHaveTrait: .italicFontMask) : baseFont
    }

    private static func normalizedPresetWeight(_ weight: Int) -> Int {
        switch weight {
        case ..<350: return 300
        case 350..<450: return 400
        case 450..<650: return 500
        default: return 700
        }
    }

    private static func presetWeights(in fonts: [CustomFont]) -> [Int] {
        let set = Set(fonts.map(\.suggestedFontWeight))
        return [300, 400, 500, 700].filter(set.contains)
    }

    private static func exactVariant(in variants: [CustomFont], weight: Int, italic: Bool) -> CustomFont? {
        variants.first { $0.suggestedFontWeight == weight && $0.isItalic == italic }
    }

    private static func preferredVariant(in variants: [CustomFont]) -> CustomFont? {
        bestVariant(in: variants, weight: 400, italic: false, preferRegularStyle: true)
    }

    private static func bestVariant(
        in variants: [CustomFont],
        weight: Int,
        italic: Bool,
        preferRegularStyle: Bool = false
    ) -> CustomFont? {
        variants.min { lhs, rhs in
            if preferRegularStyle {
                let leftRegularPenalty = CustomFont.isRegularStyle(lhs.styleName) ? 0 : 1
                let rightRegularPenalty = CustomFont.isRegularStyle(rhs.styleName) ? 0 : 1
                if leftRegularPenalty != rightRegularPenalty { return leftRegularPenalty < rightRegularPenalty }
            }

            let leftItalicPenalty = lhs.isItalic == italic ? 0 : 1
            let rightItalicPenalty = rhs.isItalic == italic ? 0 : 1
            if leftItalicPenalty != rightItalicPenalty { return leftItalicPenalty < rightItalicPenalty }

            let leftWeightDistance = abs(lhs.suggestedFontWeight - weight)
            let rightWeightDistance = abs(rhs.suggestedFontWeight - weight)
            if leftWeightDistance != rightWeightDistance { return leftWeightDistance < rightWeightDistance }

            if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
            return lhs.fileName < rhs.fileName
        }
    }
}
