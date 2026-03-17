import SwiftUI

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(_ color: Color) {
        let c = color.sRGBComponents
        self.red = Double(c.r)
        self.green = Double(c.g)
        self.blue = Double(c.b)
        self.opacity = Double(c.a)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

extension NSImage {
    /// Load an image from a security-scoped URL (e.g., from file importers).
    static func fromSecurityScopedURL(_ url: URL) -> NSImage? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return NSImage(contentsOf: url)
    }
}

extension Color {
    /// Accent color used for non-base locale UI (banner, window border).
    static let localeWarning = Color.orange

    /// Extract sRGB components from a Color. Returns (0,0,0,1) on conversion failure.
    var sRGBComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .black
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    var hexString: String {
        let c = sRGBComponents
        return String(format: "#%02x%02x%02x", Int(round(c.r * 255)), Int(round(c.g * 255)), Int(round(c.b * 255)))
    }
}
