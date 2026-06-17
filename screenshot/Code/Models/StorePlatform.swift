import Foundation

enum StorePlatform {
    case apple
    case android
}

extension DeviceCategory {
    var storePlatform: StorePlatform? {
        switch self {
        case .iphone, .ipadPro11, .ipadPro13, .macbook: .apple
        case .androidPhone, .pixel9, .androidTablet: .android
        case .invisible: nil
        }
    }
}

extension ScreenshotRow {
    /// Best guess at which store a row targets, used to pre-disable mismatched rows in the upload
    /// windows. Device frames are authoritative; the row name is a fallback when frames are silent
    /// or mixed. `nil` means unknown — such rows are never auto-disabled.
    var inferredStorePlatform: StorePlatform? {
        frameStorePlatform ?? nameStorePlatform
    }

    private var frameStorePlatform: StorePlatform? {
        let platforms = Set(shapes.compactMap { $0.type == .device ? $0.deviceCategory?.storePlatform : nil })
        return platforms.count == 1 ? platforms.first : nil
    }

    private var nameStorePlatform: StorePlatform? {
        let name = label.lowercased()
        // Avoid ambiguous bare tokens ("play", "google", "mac") that collide with common words.
        let androidKeywords = ["android", "pixel", "google play", "play store", "playstore"]
        let appleKeywords = ["ios", "iphone", "ipad", "apple", "macos", "macbook", "app store", "appstore"]
        let isAndroid = androidKeywords.contains { name.contains($0) }
        let isApple = appleKeywords.contains { name.contains($0) }
        if isAndroid == isApple { return nil }
        return isAndroid ? .android : .apple
    }
}
