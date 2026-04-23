import AppKit
import CoreText
import Foundation

/// Metadata for a user-imported font file. A single family (e.g. "Playfair Display") can
/// be imported as multiple files differing only in style (Regular, Italic, Bold...). Storing
/// the style lets the picker present each variant as a distinct option and lets rendering
/// apply the correct traits.
struct CustomFont: Hashable {
    let fileName: String
    let familyName: String
    let styleName: String?
    let postScriptName: String?
    let isItalic: Bool

    /// User-facing name used in the font picker and stored in `shape.fontName`.
    /// For "regular" styles this is just the family name (preserving backward compatibility);
    /// for non-regular styles the style is appended (e.g. "Playfair Display Italic").
    var displayName: String {
        Self.displayName(familyName: familyName, styleName: styleName)
    }

    /// Variant-specific faces should render the exact imported face, while bare family
    /// selections keep using family-based resolution so weight/italic toggles can drive
    /// the available variants.
    var exactNameForSelection: String? {
        displayName == familyName ? nil : postScriptName
    }

    static func displayName(familyName: String, styleName: String?) -> String {
        if let styleName, !isRegularStyle(styleName) {
            return "\(familyName) \(styleName)"
        }
        return familyName
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
            isItalic: symbolic.contains(.italicTrait)
        )
    }

    private static func isRegularStyle(_ style: String) -> Bool {
        let normalized = style.lowercased().trimmingCharacters(in: .whitespaces)
        return normalized.isEmpty || normalized == "regular" || normalized == "normal" || normalized == "book" || normalized == "roman"
    }
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

    static func update(with fonts: [String: CustomFont]) {
        var map: [String: CustomFont] = [:]
        for font in fonts.values {
            map[font.displayName] = font
        }
        byDisplayName = map
    }

    static func font(forDisplayName name: String) -> CustomFont? {
        byDisplayName[name]
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

    /// The display name to assign to a shape after importing a font in `familyName`.
    /// When a Regular variant is present we collapse to the bare family so the shape's
    /// existing weight/italic toggles drive Bold/Italic via NSFontManager; otherwise we
    /// fall back to a variant's display name (e.g. "Playfair Display Italic").
    static func canonicalDisplayName(for familyName: String, in fonts: [String: CustomFont]) -> String {
        // Prefer upright faces over italic when picking a default, then lex for stability
        // across runs, then fileName as a final tiebreaker.
        let variants = fonts.values
            .filter { $0.familyName == familyName }
            .sorted {
                if $0.isItalic != $1.isItalic { return !$0.isItalic }
                if $0.displayName != $1.displayName { return $0.displayName < $1.displayName }
                return $0.fileName < $1.fileName
            }
        if variants.contains(where: { $0.displayName == familyName }) {
            return familyName
        }
        return variants.first?.displayName ?? familyName
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
}
