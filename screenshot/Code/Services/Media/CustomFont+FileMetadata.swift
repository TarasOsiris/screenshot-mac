import CoreText
import Foundation

nonisolated extension CustomFont {
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

    /// Every name a stored `shape.fontName` could hold for this file: the family plus each named
    /// instance's display name. The picker writes either form, so matching a variable font on
    /// `parseMetadata`'s first descriptor alone under-matches.
    static func identityKeys(at url: URL) -> Set<String> {
        identityKeys(of: allInstances(at: url))
    }

    static func identityKeys(of faces: some Sequence<CustomFont>) -> Set<String> {
        Set(faces.flatMap { [$0.familyName, $0.displayName] })
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
