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

    /// Label without orientation (e.g. "1320×2868 — iPhone 16 Pro Max")
    var compactLabel: String {
        let suffix = subtitle.map { " — \($0)" } ?? ""
        return label + suffix
    }

    var isLandscape: Bool {
        width > height
    }

    /// Returns a copy with dimensions swapped if needed to match the requested orientation.
    func oriented(landscape: Bool) -> ScreenshotSize {
        if landscape == isLandscape { return self }
        return ScreenshotSize(width: height, height: width, subtitle: subtitle)
    }
}

struct DisplayCategory: Identifiable {
    let id = UUID()
    let name: String
    let deviceCategory: DeviceCategory?
    let sizes: [ScreenshotSize]
    let isLandscapeOnly: Bool

    /// Create a category with portrait sizes that auto-generate landscape variants.
    init(name: String, deviceCategory: DeviceCategory? = nil, portraitSizes: [(w: CGFloat, h: CGFloat, subtitle: String)]) {
        self.name = name
        self.deviceCategory = deviceCategory
        self.isLandscapeOnly = false
        self.sizes = portraitSizes.flatMap { size in [
            ScreenshotSize(width: size.w, height: size.h, subtitle: size.subtitle),
            ScreenshotSize(width: size.h, height: size.w, subtitle: size.subtitle),
        ]}
    }

    /// Create a category with landscape-only sizes (no portrait variant).
    init(name: String, deviceCategory: DeviceCategory? = nil, landscapeSizes: [(w: CGFloat, h: CGFloat, subtitle: String)]) {
        self.name = name
        self.deviceCategory = deviceCategory
        self.isLandscapeOnly = true
        self.sizes = landscapeSizes.map {
            ScreenshotSize(width: $0.w, height: $0.h, subtitle: $0.subtitle)
        }
    }

    /// Canonical sizes without orientation duplicates (portrait for phone/tablet, all for landscape-only).
    var canonicalSizes: [ScreenshotSize] {
        if isLandscapeOnly { return sizes }
        return sizes.filter { !$0.isLandscape }
    }
}

let displayCategories: [DisplayCategory] = [
    DisplayCategory(name: "iPhone 6.9\" Display", deviceCategory: .iphone, portraitSizes: [
        (1320, 2868, "iPhone 16 Pro Max / 17 Pro Max"),
        (1290, 2796, "iPhone 16 Plus / 15 Pro Max / 15 Plus"),
        (1260, 2736, "iPhone Air / 14 Pro Max"),
    ]),
    DisplayCategory(name: "iPhone 6.5\" Display", deviceCategory: .iphone, portraitSizes: [
        (1284, 2778, "iPhone 14 Plus / 13 Pro Max / 12 Pro Max"),
        (1242, 2688, "iPhone 11 Pro Max / XS Max / XR"),
    ]),
    DisplayCategory(name: "iPhone 6.3\" Display", deviceCategory: .iphone, portraitSizes: [
        (1206, 2622, "iPhone 17 / 16 Pro"),
        (1179, 2556, "iPhone 16 / 15 Pro / 15 / 14 Pro"),
    ]),
    DisplayCategory(name: "iPhone 6.1\" Display", deviceCategory: .iphone, portraitSizes: [
        (1170, 2532, "iPhone 14 / 13 / 12"),
        (1125, 2436, "iPhone 11 Pro / XS / X"),
        (1080, 2340, "iPhone 17e / 16e"),
    ]),
    DisplayCategory(name: "iPhone 5.5\" Display", deviceCategory: .iphone, portraitSizes: [
        (1242, 2208, "iPhone 8 Plus / 7 Plus / 6S Plus"),
    ]),
    DisplayCategory(name: "iPad 13\" Display", deviceCategory: .ipadPro13, portraitSizes: [
        (2064, 2752, "iPad Pro 13\" (M4+) / iPad Air"),
        (2048, 2732, "iPad Pro 12.9\" (3rd–6th gen)"),
    ]),
    DisplayCategory(name: "iPad 11\" Display", deviceCategory: .ipadPro11, portraitSizes: [
        (1488, 2266, "iPad Pro 11\" (M4+) / iPad Air / iPad mini"),
        (1668, 2420, "iPad Pro 11\" (M4)"),
        (1668, 2388, "iPad Pro 11\" (3rd/4th gen)"),
        (1640, 2360, "iPad (10th gen) / iPad mini (6th gen)"),
    ]),
    DisplayCategory(name: "Mac Desktop", deviceCategory: .macbook, landscapeSizes: [
        (2880, 1800, "Retina 16:10"),
        (2560, 1600, "Retina 16:10"),
        (1440, 900, "Standard 16:10"),
        (1280, 800, "Standard 16:10"),
    ]),
    DisplayCategory(name: "Android Phone", deviceCategory: .androidPhone, portraitSizes: [
        (1080, 1920, "Standard 16:9"),
        (1080, 2160, "Modern 18:9"),
        (1440, 2560, "High-res 16:9"),
    ]),
    DisplayCategory(name: "Android 7\" Tablet", deviceCategory: .androidTablet, portraitSizes: [
        (1200, 1920, "Standard 16:10"),
    ]),
    DisplayCategory(name: "Android 10\" Tablet", deviceCategory: .androidTablet, portraitSizes: [
        (1600, 2560, "High-res 16:10"),
        (1920, 2560, "Standard 4:3"),
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
