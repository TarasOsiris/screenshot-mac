import CoreText
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Cross-platform access to the system's installed font families. macOS uses NSFontManager;
/// iOS uses UIFont. Custom (process-registered) fonts are layered on by AppState.
enum PlatformFonts {
    static var systemFamilyNames: [String] {
        #if os(macOS)
        return NSFontManager.shared.availableFontFamilies
        #else
        return UIFont.familyNames
        #endif
    }

    private static var cachedFamilyNameSet: Set<String>?

    /// Cached: enumerating font families allocates hundreds of strings per call, and
    /// render fallbacks (thumbnails, template drags) probe this set per render.
    /// `AppState.refreshAvailableFontFamilies` invalidates it when fonts change.
    static var familyNameSet: Set<String> {
        if let cachedFamilyNameSet { return cachedFamilyNameSet }
        let set = Set(systemFamilyNames)
        cachedFamilyNameSet = set
        return set
    }

    static func invalidateFamilyNameCache() {
        cachedFamilyNameSet = nil
    }
}

extension NSFont {
    var hasBoldTrait: Bool {
        #if os(macOS)
        fontDescriptor.symbolicTraits.contains(.bold)
        #else
        fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    var hasItalicTrait: Bool {
        #if os(macOS)
        fontDescriptor.symbolicTraits.contains(.italic)
        #else
        fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }
}

/// Cross-platform background colors for chrome that previously used AppKit-only system colors.
extension Color {
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var platformUnderPageBackground: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var platformTextBackground: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var platformSeparator: Color {
        #if os(macOS)
        Color(nsColor: .separatorColor)
        #else
        Color(uiColor: .separator)
        #endif
    }
}

#if os(iOS)
extension UIFont.Weight {
    /// Map an AppKit NSFontManager weight (0…15, 5 ≈ regular, 9 ≈ bold) to a UIFont.Weight.
    /// Mirrors the macOS `RichTextUtils.nsFontWeight(for:)` map so the same shape renders at
    /// the same weight on both platforms (editor↔export parity across devices).
    init(managerWeight: Int) {
        switch managerWeight {
        case ..<4: self = .thin
        case 4: self = .light
        case 5: self = .regular
        case 6: self = .medium
        case 7...8: self = .semibold
        case 9...10: self = .bold
        default: self = .heavy
        }
    }
}

extension UIFont {
    /// Returns this font with the italic symbolic trait added (falls back to self if the
    /// descriptor can't take it). Shared by the font-resolution paths.
    func addingItalic() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic)) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }

    /// Returns this font with the given symbolic trait toggled on/off (falls back to self if the
    /// descriptor can't take it). Used by rich-text bold/italic formatting.
    func toggling(_ trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
        var traits = fontDescriptor.symbolicTraits
        if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif
