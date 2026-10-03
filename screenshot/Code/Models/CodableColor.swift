import SwiftUI

nonisolated struct CodableColor: Codable, Equatable {
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
        try container.encode(hexKey)
    }

    /// The 8-bit form the file stores — and so the precision at which two colors are the same.
    var hexKey: String {
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))
        let a = Int(round(opacity * 255))
        return a == 255
            ? String(format: "#%02X%02X%02X", r, g, b)
            : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    /// Parses "#RRGGBB" / "#RRGGBBAA" (the encode format above); the "#" is optional.
    init?(hexString: String) {
        let hexStr = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard hexStr.count == 6 || hexStr.count == 8,
              let value = UInt64(hexStr, radix: 16) else { return nil }
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

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        guard hex.hasPrefix("#") else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hex color")
        }
        if let parsed = CodableColor(hexString: hex) {
            self = parsed
            return
        }
        // Legacy tolerance: existing files may hold nonstandard hex (e.g. CSS shorthand "#fff"
        // from SVG-imported templates). The historical Scanner-based decode produced a
        // wrong-but-loadable color for those; failing here would fail the whole project load.
        let hexStr = String(hex.dropFirst())
        var value: UInt64 = 0
        Scanner(string: hexStr).scanHexInt64(&value)
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
