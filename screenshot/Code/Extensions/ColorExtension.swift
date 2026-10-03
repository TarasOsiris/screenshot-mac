import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension Color {
    /// Extract sRGB components from a Color. Returns (0,0,0,1) on conversion failure.
    var sRGBComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .black
        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
        return (r, g, b, a)
    }

    var hexString: String {
        let c = sRGBComponents
        return String(format: "#%02x%02x%02x", Int(round(c.r * 255)), Int(round(c.g * 255)), Int(round(c.b * 255)))
    }
}
