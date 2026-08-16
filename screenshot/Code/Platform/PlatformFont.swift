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

    /// Clears the cache whenever CTFontManager registrations change (covers both
    /// in-process custom-font registration and system-wide installs). Installed
    /// lazily on first cache access.
    private static let fontChangeObserver: NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSNotification.Name(kCTFontManagerRegisteredFontsChangedNotification as String),
        object: nil,
        queue: .main
    ) { _ in
        MainActor.assumeIsolated { cachedFamilyNameSet = nil }
    }

    /// Cached: enumerating font families allocates hundreds of strings per call, and
    /// render fallbacks (thumbnails, template drags) probe this set per render.
    static var familyNameSet: Set<String> {
        if let cachedFamilyNameSet { return cachedFamilyNameSet }
        _ = fontChangeObserver
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

/// The CSS numeric weight (100…900) stored on text shapes, bucketed once. The canvas, the
/// properties bar, and RTF round-tripping all read the same buckets so they cannot disagree
/// about where `bold` starts.
nonisolated enum CSSFontWeight {
    case thin, light, regular, medium, semibold, bold, heavy

    init(css: Int) {
        switch css {
        case ...299: self = .thin
        case 300...399: self = .light
        case 400...499: self = .regular
        case 500...599: self = .medium
        case 600...699: self = .semibold
        case 700...799: self = .bold
        default: self = .heavy
        }
    }

    var font: Font.Weight {
        switch self {
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    var platform: NSFont.Weight {
        switch self {
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        }
    }

    /// NSFontManager's 0…15 scale (5 ≈ regular, 9 ≈ bold).
    var manager: Int {
        switch self {
        case .thin: 3
        case .light: 4
        case .regular: 5
        case .medium: 6
        case .semibold: 8
        case .bold: 9
        case .heavy: 11
        }
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
