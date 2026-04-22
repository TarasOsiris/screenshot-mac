import Foundation
import SwiftUI

enum DeviceCategory: String, Codable, CaseIterable {
    case iphone
    case ipadPro11
    case ipadPro13
    case macbook
    case androidPhone = "android"
    case pixel9
    case androidTablet
    case invisible

    var label: String {
        switch self {
        case .iphone: "iPhone"
        case .ipadPro11: "iPad Pro 11\""
        case .ipadPro13: "iPad Pro 13\""
        case .macbook: "MacBook"
        case .androidPhone: String(localized: "Android Phone")
        case .pixel9: String(localized: "Abstract Pixel 9")
        case .androidTablet: String(localized: "Android Tablet")
        case .invisible: String(localized: "Invisible")
        }
    }

    var icon: String {
        switch self {
        case .iphone: "iphone"
        case .ipadPro11, .ipadPro13: "ipad"
        case .macbook: "laptopcomputer"
        case .androidPhone, .pixel9: "iphone.gen3"
        case .androidTablet: "ipad.gen2"
        case .invisible: "rectangle.dashed"
        }
    }

    /// Suggested screenshot size preset string for this device category.
    var suggestedSizePreset: String {
        switch self {
        case .iphone: "1206x2622"
        case .ipadPro11: "1668x2420"
        case .ipadPro13: "2064x2752"
        case .macbook: "2880x1800"
        case .androidPhone: "1080x1920"
        case .pixel9: "1280x2856"
        case .androidTablet: "1200x1920"
        case .invisible: "1206x2622"
        }
    }

    /// Pre-computed map from normalized size preset (portrait) → device category.
    private static let categoryBySizePreset: [String: DeviceCategory] = {
        var map: [String: DeviceCategory] = [:]
        for category in displayCategories {
            guard let deviceCategory = category.deviceCategory else { continue }
            for size in category.sizes {
                let w = Int(min(size.width, size.height))
                let h = Int(max(size.width, size.height))
                map["\(w)x\(h)"] = deviceCategory
            }
        }
        return map
    }()

    /// Best matching device category for a screenshot size preset string.
    static func suggestedCategory(forSizePreset preset: String) -> DeviceCategory? {
        guard let size = parseSizeString(preset) else { return nil }
        let w = Int(min(size.width, size.height))
        let h = Int(max(size.width, size.height))
        return categoryBySizePreset["\(w)x\(h)"]
    }

    /// Body dimensions (without side buttons).
    /// iPhone 17: 71.5 x 149.6 mm at scale 3.077 px/mm → 220 x ~460.
    /// Height adjusted to 468 so screen area ratio matches real iPhone screenshots (~0.46).
    /// iPad Pro 11": 177.5 x 249.7 mm → 546 x 768.
    /// iPad Pro 13": 215.5 x 281.6 mm → 663 x 867.
    /// MacBook: generic 16:10 landscape proportion.
    /// Android Phone: generic modern phone ~72 x 153 mm → 221 x 470.
    /// Pixel 9: abstract Pixel 9 template proportions from 452×964 SVG → 226 x 482.
    /// Android Tablet: generic tablet ~165 x 254 mm → 508 x 782.
    var bodyDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .iphone: (220, 468)
        case .ipadPro11: (546, 768)
        case .ipadPro13: (663, 867)
        case .macbook: (640, 420)
        case .androidPhone: (221, 470)
        case .pixel9: (226, 482)
        case .androidTablet: (508, 782)
        case .invisible: (220, 468)
        }
    }

    /// Depth of side buttons protruding from body edge.
    /// iPads and MacBooks have flush buttons (no protrusion).
    var buttonDepth: CGFloat {
        switch self {
        case .iphone, .androidPhone: 2.5
        case .ipadPro11, .ipadPro13, .macbook, .pixel9, .androidTablet, .invisible: 0
        }
    }

    /// Bezel dimensions in base units (px at 3.077 px/mm scale).
    var bezels: (lr: CGFloat, tb: CGFloat) {
        switch self {
        case .iphone: (4.34, 4.43)
        case .ipadPro11: (26.5, 25.8)
        case .ipadPro13: (27.0, 26.0)
        case .macbook: (40, 40)
        case .androidPhone: (4.0, 4.0)
        case .pixel9: (10, 10)
        case .androidTablet: (18.0, 18.0)
        case .invisible: (0, 0)
        }
    }

    /// Body corner radius in base units.
    var bodyCornerRadius: CGFloat {
        switch self {
        case .iphone: 34
        case .ipadPro11, .ipadPro13: 55
        case .macbook: 20
        case .androidPhone: 30
        case .pixel9: 38
        case .androidTablet: 40
        case .invisible: 0
        }
    }

    /// Screen corner radius in base units.
    var screenCornerRadius: CGFloat {
        switch self {
        case .iphone: 33
        case .ipadPro11, .ipadPro13: 29
        case .macbook: 10
        case .androidPhone, .pixel9: 28
        case .androidTablet: 20
        case .invisible: 0
        }
    }

    /// Total bounding box including side buttons.
    var baseDimensions: (width: CGFloat, height: CGFloat) {
        let body = bodyDimensions
        return (body.width + buttonDepth * 2, body.height)
    }
}
