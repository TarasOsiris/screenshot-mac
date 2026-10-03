#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreText
import Foundation

/// Process-wide lookup so rendering code can resolve a `shape.fontName` (which may be a
/// custom font's display name) back to family + traits without having to thread the full
/// custom-font dictionary through every call site. `CustomFontLibrary` keeps this in sync via
/// `refreshAvailableFamilies()`.
enum CustomFontRegistry {
    struct ResolvedFont: Equatable {
        let family: String
        let exactName: String?
        let italic: Bool
    }

    private static var byDisplayName: [String: CustomFont] = [:]
    private static var byFamily: [String: [CustomFont]] = [:]

    /// Picker order (family, upright before italic, light to heavy), one face per display name —
    /// the name is what `shape.fontName` stores, so two files sharing one resolve to the first.
    nonisolated static func faces(_ fonts: some Sequence<CustomFont>) -> [CustomFont] {
        var seenDisplayNames = Set<String>()
        return fonts.sorted { lhs, rhs in
            if lhs.familyName != rhs.familyName { return lhs.familyName < rhs.familyName }
            if lhs.isItalic != rhs.isItalic { return !lhs.isItalic }
            if lhs.typographicWeight != rhs.typographicWeight { return lhs.typographicWeight < rhs.typographicWeight }
            return CustomFont.plainerStyleFirst(lhs, rhs)
        }
        .filter { seenDisplayNames.insert($0.displayName).inserted }
    }

    static func update(with fonts: [CustomFont]) {
        let ordered = faces(fonts)
        byDisplayName = Dictionary(uniqueKeysWithValues: ordered.map { ($0.displayName, $0) })
        byFamily = Dictionary(grouping: ordered, by: \.familyName)
    }

    static func withTemporaryFonts<Result>(
        _ fonts: [CustomFont],
        perform: () throws -> Result
    ) rethrows -> Result {
        let previousByDisplayName = byDisplayName
        let previousByFamily = byFamily
        update(with: fonts)
        defer {
            byDisplayName = previousByDisplayName
            byFamily = previousByFamily
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
        // Stay on the current face's own weight within its preset, so italicizing Black lands on
        // Black Italic rather than the preset's Bold Italic.
        let current = byDisplayName[name]
        let targetWeight = current.flatMap { $0.suggestedFontWeight == requestedWeight ? $0.typographicWeight : nil }

        if let exact = exactVariant(in: variants, weight: requestedWeight, italic: requestedItalic, closestTo: targetWeight) {
            return exact.selectionResult()
        }

        guard current == nil,
              let best = bestVariant(in: variants, weight: requestedWeight, italic: requestedItalic) else {
            return nil
        }
        return best.selectionResult()
    }

    static func preferredSelection(for familyName: String, in faces: [CustomFont]) -> ImportedCustomFontSelection? {
        let variants = faces.filter { $0.familyName == familyName }
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
        guard let variants = byFamily[family], !variants.isEmpty else { return nil }
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

    /// The weights the picker offers; `normalizedPresetWeight` rounds every face onto one of these.
    static let presetWeightBuckets = [300, 400, 500, 700]

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
        return presetWeightBuckets.filter(set.contains)
    }

    /// A variable font puts several faces in one preset (Thin/ExtraLight/Light are all 300), so
    /// pick the one nearest the preset itself — or `closestTo`.
    private static func exactVariant(in variants: [CustomFont], weight: Int, italic: Bool, closestTo target: Int? = nil) -> CustomFont? {
        let candidates = variants.filter { $0.suggestedFontWeight == weight && $0.isItalic == italic }
        return bestMatch(in: candidates, weight: target ?? weight, italic: italic, on: \.typographicWeight, tieBreak: CustomFont.plainerStyleFirst)
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
        bestMatch(
            in: variants,
            weight: weight,
            italic: italic,
            on: \.suggestedFontWeight,
            preferRegularStyle: preferRegularStyle,
            tieBreak: CustomFont.plainerStyleFirst
        )
    }
}
