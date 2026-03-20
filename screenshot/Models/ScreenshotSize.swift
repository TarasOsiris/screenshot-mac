import Foundation
import SwiftUI

struct ScreenshotSize: Identifiable {
    let id = UUID()
    let width: CGFloat
    let height: CGFloat
    let subtitle: String?

    init(width: CGFloat, height: CGFloat, subtitle: String? = nil) {
        self.width = width
        self.height = height
        self.subtitle = subtitle
    }

    var label: String {
        "\(Int(width))\u{00d7}\(Int(height))"
    }

    var displayLabel: String {
        let orientation = isLandscape ? "Landscape" : "Portrait"
        let suffix = subtitle.map { " — \($0)" } ?? ""
        return label + " " + orientation + suffix
    }

    var isLandscape: Bool {
        width > height
    }
}

struct DisplayCategory: Identifiable {
    let id = UUID()
    let name: String
    let sizes: [ScreenshotSize]

    /// Create a category with portrait sizes that auto-generate landscape variants.
    init(name: String, portraitSizes: [(w: CGFloat, h: CGFloat, subtitle: String)]) {
        self.name = name
        self.sizes = portraitSizes.flatMap { size in [
            ScreenshotSize(width: size.w, height: size.h, subtitle: size.subtitle),
            ScreenshotSize(width: size.h, height: size.w, subtitle: size.subtitle),
        ]}
    }

    /// Create a category with landscape-only sizes (no portrait variant).
    init(name: String, landscapeSizes: [(w: CGFloat, h: CGFloat, subtitle: String)]) {
        self.name = name
        self.sizes = landscapeSizes.map {
            ScreenshotSize(width: $0.w, height: $0.h, subtitle: $0.subtitle)
        }
    }
}

let displayCategories: [DisplayCategory] = [
    DisplayCategory(name: "iPhone 6.9\" Display", portraitSizes: [
        (1320, 2868, "iPhone 16 Pro Max / 17 Pro Max"),
    ]),
    DisplayCategory(name: "iPhone 6.7\" Display", portraitSizes: [
        (1290, 2796, "iPhone 16 Plus / 15 Pro Max"),
    ]),
    DisplayCategory(name: "iPhone 6.5\" Display", portraitSizes: [
        (1284, 2778, "iPhone 14 Pro Max"),
        (1242, 2688, "iPhone 11 Pro Max / XS Max"),
    ]),
    DisplayCategory(name: "iPhone 6.3\" Display", portraitSizes: [
        (1206, 2622, "iPhone 16 Pro / 17 / 17 Pro"),
    ]),
    DisplayCategory(name: "iPhone 6.1\" Display", portraitSizes: [
        (1179, 2556, "iPhone 16 / 15 / 14 Pro"),
        (1260, 2736, "iPhone Air"),
    ]),
    DisplayCategory(name: "iPad Pro 13\" Display", portraitSizes: [
        (2064, 2752, "iPad Pro 13\" (M4)"),
        (2048, 2732, "iPad Pro 12.9\" (3rd–6th gen)"),
    ]),
    DisplayCategory(name: "iPad Pro 11\" Display", portraitSizes: [
        (1668, 2420, "iPad Pro 11\" (M4)"),
        (1668, 2388, "iPad Pro 11\" (3rd/4th gen)"),
    ]),
    DisplayCategory(name: "Mac Desktop", landscapeSizes: [
        (2560, 1664, "MacBook Air 13\" (M2+)"),
        (2880, 1864, "MacBook Air 15\" (M2+)"),
        (3024, 1964, "MacBook Pro 14\" (M3+)"),
        (3456, 2234, "MacBook Pro 16\" (M3+)"),
        (4480, 2520, "iMac 24\" (M3+)"),
        (1280, 800, "MacBook Air 13\" (legacy)"),
        (1440, 900, "MacBook Pro 15\" (legacy)"),
    ]),
    DisplayCategory(name: "Android Phone", portraitSizes: [
        (1080, 1920, "Standard 16:9"),
        (1080, 2340, "Modern 19.5:9"),
        (1440, 3120, "High-res 19.5:9"),
    ]),
    DisplayCategory(name: "Android Tablet", portraitSizes: [
        (1200, 1920, "Standard"),
        (1600, 2560, "High-res QHD"),
    ]),
]

func parseSizeString(_ value: String) -> (width: CGFloat, height: CGFloat)? {
    let parts = value.split(separator: "x")
    guard parts.count == 2,
          let w = Double(parts[0]),
          let h = Double(parts[1]) else { return nil }
    return (CGFloat(w), CGFloat(h))
}

func presetLabel(forWidth width: CGFloat, height: CGFloat) -> String {
    for category in displayCategories {
        if let size = category.sizes.first(where: { $0.width == width && $0.height == height }) {
            let orientation = size.isLandscape ? "Landscape" : "Portrait"
            return "\(category.name) \(orientation)"
        }
    }
    return "\(Int(width))\u{00d7}\(Int(height))"
}
