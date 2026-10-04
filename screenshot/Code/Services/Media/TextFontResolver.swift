#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum TextFontResolver {
    private static let fontCache: NSCache<NSString, NSFont> = {
        let cache = NSCache<NSString, NSFont>()
        cache.countLimit = 200
        return cache
    }()

    static func resolvedFont(
        shape: CanvasShapeModel,
        availableFontFamilies: Set<String>,
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool = false
    ) -> NSFont {
        let customName = customFontName(for: shape, availableFontFamilies: availableFontFamilies)
        let resolvedCustomFont = customName.map(CustomFontRegistry.resolve)
        let resolvedName = resolvedCustomFont?.exactName ?? resolvedCustomFont?.family ?? "__system__"
        let cacheKey = "\(resolvedName)|\(size)|\(weight.rawValue)|\(italic)" as NSString
        if let cached = fontCache.object(forKey: cacheKey) {
            return cached
        }

        let resolved: NSFont
        if let name = customName {
            resolved = CustomFontRegistry.resolveNSFont(
                name: name,
                size: size,
                managerWeight: fontManagerWeight(for: weight),
                italic: italic
            )
        } else {
            resolved = italicized(NSFont.systemFont(ofSize: size, weight: weight), italic: italic)
        }
        fontCache.setObject(resolved, forKey: cacheKey)
        return resolved
    }

    private static func customFontName(for shape: CanvasShapeModel, availableFontFamilies: Set<String>) -> String? {
        guard let name = shape.fontName, !name.isEmpty else { return nil }
        if CustomFontRegistry.font(forDisplayName: name) != nil { return name }
        if availableFontFamilies.contains(name) { return name }
        return nil
    }

    private static func italicized(_ font: NSFont, italic: Bool) -> NSFont {
        guard italic else { return font }
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        return font.addingItalic()
        #endif
    }

    private static func fontManagerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: return 2
        case .thin:       return 3
        case .light:      return 4
        case .regular:    return 5
        case .medium:     return 6
        case .semibold:   return 8
        case .bold:       return 9
        case .heavy:      return 11
        case .black:      return 14
        default:          return 5
        }
    }
}
