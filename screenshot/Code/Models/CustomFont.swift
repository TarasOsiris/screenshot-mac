#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
    /// Full 100–900 CSS weight inferred from the style name, used to pick the exact named
    /// instance of a (variable) font when resolving a bare family name. Distinct from
    /// `suggestedFontWeight`, which buckets to the picker's presets (300/400/500/700).
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
              let first = descriptors.first else {
            return nil
        }
        return make(from: first, fileName: url.lastPathComponent)
    }

    /// Every named instance a font file exposes. A variable font reports one descriptor per
    /// named instance (Thin…Black); a static font reports a single descriptor. Used to build
    /// the per-family variant table so a bare family name (e.g. "DM Sans") can resolve to the
    /// exact named instance for a requested weight — required on iOS, where process-registered
    /// variable fonts can't be instantiated reliably via `UIFontDescriptor(.family:)`.
    static func allInstances(at url: URL) -> [CustomFont] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        return descriptors.compactMap { make(from: $0, fileName: url.lastPathComponent) }
    }

    private static func make(from descriptor: CTFontDescriptor, fileName: String) -> CustomFont? {
        guard let familyName = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        let styleName = CTFontDescriptorCopyAttribute(descriptor, kCTFontStyleNameAttribute) as? String
        let traits = (CTFontDescriptorCopyAttribute(descriptor, kCTFontTraitsAttribute) as? [String: Any]) ?? [:]
        let symbolic = (traits[kCTFontSymbolicTrait as String] as? UInt32).map { CTFontSymbolicTraits(rawValue: $0) } ?? []

        return CustomFont(
            fileName: fileName,
            familyName: familyName,
            styleName: styleName,
            postScriptName: CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String,
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
    /// All named instances per family (every weight a variable font exposes), used only to
    /// resolve a bare family name to an exact PostScript name. Kept separate from `byFamily`
    /// so the picker/control-state still see one primary face per imported file.
    private static var instancesByFamily: [String: [CustomFont]] = [:]

    static func update(with fonts: [String: CustomFont], instances: [CustomFont] = []) {
        var map: [String: CustomFont] = [:]
        var familyMap: [String: [CustomFont]] = [:]
        for font in fonts.values {
            map[font.displayName] = font
            familyMap[font.familyName, default: []].append(font)
        }
        byDisplayName = map
        byFamily = familyMap

        var instanceMap: [String: [CustomFont]] = [:]
        for font in instances {
            instanceMap[font.familyName, default: []].append(font)
        }
        instancesByFamily = instanceMap
    }

    static func withTemporaryFonts<Result>(
        _ fonts: [String: CustomFont],
        instances: [CustomFont],
        perform: () throws -> Result
    ) rethrows -> Result {
        let previousByDisplayName = byDisplayName
        let previousByFamily = byFamily
        let previousInstancesByFamily = instancesByFamily
        update(with: fonts, instances: instances)
        defer {
            byDisplayName = previousByDisplayName
            byFamily = previousByFamily
            instancesByFamily = previousInstancesByFamily
        }
        return try perform()
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
        #if os(macOS)
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
        } else if let psName = postScriptName(forFamily: resolved.family, managerWeight: managerWeight, italic: effectiveItalic),
                  let font = NSFont(name: psName, size: size) {
            // NSFontManager can't see process-registered fonts, so a bare custom family
            // ("DM Sans" at weight 700) only resolves through its registered named
            // instance's PostScript name — CTFontCreateWithName below ignores the weight.
            baseFont = font
        } else {
            baseFont = CTFontCreateWithName(resolved.family as CFString, size, nil) as NSFont
        }
        return effectiveItalic ? fm.convert(baseFont, toHaveTrait: .italicFontMask) : baseFont
        #else
        // Prefer an exact registered PostScript face: UIFontDescriptor(.family:) can't
        // instantiate process-registered (variable) fonts — family-named text renders tofu.
        let exactName = resolved.exactName
            ?? postScriptName(forFamily: resolved.family, managerWeight: managerWeight, italic: effectiveItalic)
        let base: UIFont
        if let exactName, let font = UIFont(name: exactName, size: size) {
            base = font
        } else {
            let weight = UIFont.Weight(managerWeight: managerWeight)
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: resolved.family,
                .traits: [UIFontDescriptor.TraitKey.weight: weight],
            ])
            base = UIFont(descriptor: descriptor, size: size)
        }
        // The named instance already carries its own slant; only synthesize italic when the
        // chosen face isn't itself italic (matches the exact-PostScript path above).
        return effectiveItalic ? base.addingItalic() : base
        #endif
    }

    /// Best registered named-instance PostScript name for a custom family at the requested
    /// weight/italic, or nil if the family isn't a known custom font.
    static func postScriptName(forFamily family: String, managerWeight: Int, italic: Bool) -> String? {
        guard let variants = instancesByFamily[family], !variants.isEmpty else { return nil }
        return bestInstance(in: variants, weight: cssWeight(forManagerWeight: managerWeight), italic: italic)?.postScriptName
    }

    /// Maps NSFontManager's 0–15 weight scale onto the 100–900 CSS scale used to pick a named
    /// instance.
    private static func cssWeight(forManagerWeight weight: Int) -> Int {
        switch weight {
        case ...2: return 200
        case 3...4: return 300
        case 5: return 400
        case 6: return 500
        case 7...8: return 600
        case 9...10: return 700
        case 11...13: return 800
        default: return 900
        }
    }

    private static func bestInstance(in variants: [CustomFont], weight: Int, italic: Bool) -> CustomFont? {
        bestMatch(in: variants, weight: weight, italic: italic, on: \.typographicWeight) {
            ($0.postScriptName ?? "") < ($1.postScriptName ?? "")
        }
    }

    /// Shared selection ladder for picking the closest face to a requested weight/italic:
    /// optional regular-style preference, then italic match, then distance on the given weight
    /// scale, then a caller-supplied stable tiebreak.
    private static func bestMatch(
        in variants: [CustomFont],
        weight requested: Int,
        italic: Bool,
        on weightKey: KeyPath<CustomFont, Int>,
        preferRegularStyle: Bool = false,
        tieBreak: (CustomFont, CustomFont) -> Bool
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

            let leftWeightDistance = abs(lhs[keyPath: weightKey] - requested)
            let rightWeightDistance = abs(rhs[keyPath: weightKey] - requested)
            if leftWeightDistance != rightWeightDistance { return leftWeightDistance < rightWeightDistance }

            return tieBreak(lhs, rhs)
        }
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
        bestMatch(in: variants, weight: weight, italic: italic, on: \.suggestedFontWeight, preferRegularStyle: preferRegularStyle) {
            $0.displayName != $1.displayName ? $0.displayName < $1.displayName : $0.fileName < $1.fileName
        }
    }
}
