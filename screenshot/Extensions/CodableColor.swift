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

    // Encode as hex string: "#RRGGBB" (opaque) or "#RRGGBBAA"
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        let a = Int(round(opacity * 255))
        if a == 255 {
            try container.encode(String(format: "#%02X%02X%02X", r, g, b))
        } else {
            try container.encode(String(format: "#%02X%02X%02X%02X", r, g, b, a))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard hex.hasPrefix("#") else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex color")
        }
        let hexStr = String(hex.dropFirst())
        let scanner = Scanner(string: hexStr)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        if hexStr.count == 6 {
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
            opacity = 1.0
        } else {
            red = Double((value >> 24) & 0xFF) / 255.0
            green = Double((value >> 16) & 0xFF) / 255.0
            blue = Double((value >> 8) & 0xFF) / 255.0
            opacity = Double(value & 0xFF) / 255.0
        }
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
