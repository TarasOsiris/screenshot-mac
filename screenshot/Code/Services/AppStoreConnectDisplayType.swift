import Foundation

/// Screenshot display type — the device/size bucket a screenshot set targets.
/// Some newer App Store labels still upload through older `screenshotDisplayType`
/// enum values because the ASC API does not expose a distinct enum case for them.
enum ASCDisplayType: String, CaseIterable, Identifiable {
    // iPhone
    case iphone69 = "APP_IPHONE_69"  // 6.9" (1320x2868) — 16/17 Pro Max
    case iphone67 = "APP_IPHONE_67"  // 6.7" (1290x2796) — 16 Plus / 15 Pro Max
    case iphone65 = "APP_IPHONE_65"  // 6.5" (1242x2688 / 1284x2778)
    case iphone63 = "APP_IPHONE_63"  // 6.3" (1206x2622) — 17 / 16 Pro
    case iphone61 = "APP_IPHONE_61"  // 6.1" (1170x2532 / 1179x2556 / 1080x2340)
    case iphone58 = "APP_IPHONE_58"  // 5.8" (1125x2436)
    case iphone55 = "APP_IPHONE_55"  // 5.5" (1242x2208)
    case iphone47 = "APP_IPHONE_47"  // 4.7" (750x1334)
    case iphone40 = "APP_IPHONE_40"  // 4.0" (640x1096)
    case iphone35 = "APP_IPHONE_35"  // 3.5" (640x920)

    // iPad
    case ipadPro129M4 = "APP_IPAD_PRO_129_M4"     // 13" (2064x2752)
    case ipadPro3Gen129 = "APP_IPAD_PRO_3GEN_129" // 12.9" (2048x2732)
    case ipadPro11M4 = "APP_IPAD_PRO_11_M4"       // 11" (1488x2266)
    case ipadPro3Gen11 = "APP_IPAD_PRO_3GEN_11"   // 11" (1668x2388 / 1668x2420)
    case ipad105 = "APP_IPAD_105"                 // 10.5" (1668x2224)
    case ipad97 = "APP_IPAD_97"                   // 9.7" (1536x2048)

    // Mac
    case desktop = "APP_DESKTOP"                  // 2880x1800, 2560x1600, 1440x900, 1280x800

    // Apple Watch / TV (not targeted by Screenshot Bro but kept for completeness)
    case watchUltra = "APP_WATCH_ULTRA"
    case watchSeries7 = "APP_WATCH_SERIES_7"
    case watchSeries4 = "APP_WATCH_SERIES_4"
    case watchSeries3 = "APP_WATCH_SERIES_3"
    case appleTV = "APP_APPLE_TV"
    case visionPro = "APP_APPLE_VISION_PRO"

    var id: String { rawValue }

    /// The enum value accepted by App Store Connect's `screenshotDisplayType` API field.
    var appStoreConnectValue: String {
        switch self {
        case .iphone69:
            return ASCDisplayType.iphone67.rawValue
        case .iphone63:
            return ASCDisplayType.iphone61.rawValue
        case .ipadPro129M4:
            return ASCDisplayType.ipadPro3Gen129.rawValue
        case .ipadPro11M4:
            return ASCDisplayType.ipadPro3Gen11.rawValue
        default:
            return rawValue
        }
    }

    enum Family {
        case iphone
        case ipad
        case mac
        case other
    }

    var family: Family {
        switch self {
        case .iphone69, .iphone67, .iphone65, .iphone63, .iphone61, .iphone58, .iphone55, .iphone47, .iphone40, .iphone35:
            return .iphone
        case .ipadPro129M4, .ipadPro3Gen129, .ipadPro11M4, .ipadPro3Gen11, .ipad105, .ipad97:
            return .ipad
        case .desktop:
            return .mac
        default:
            return .other
        }
    }

    var label: String {
        switch self {
        case .iphone69: return "iPhone 6.9\" Display (1320×2868)"
        case .iphone67: return "iPhone 6.7\" Display (1290×2796)"
        case .iphone65: return "iPhone 6.5\" Display (1242×2688 / 1284×2778)"
        case .iphone63: return "iPhone 6.3\" Display (1206×2622)"
        case .iphone61: return "iPhone 6.1\" Display (1170×2532 / 1179×2556)"
        case .iphone58: return "iPhone 5.8\" Display (1125×2436)"
        case .iphone55: return "iPhone 5.5\" Display (1242×2208)"
        case .iphone47: return "iPhone 4.7\" Display (750×1334)"
        case .iphone40: return "iPhone 4.0\" Display"
        case .iphone35: return "iPhone 3.5\" Display"
        case .ipadPro129M4: return "iPad Pro 13\" M4 (2064×2752)"
        case .ipadPro3Gen129: return "iPad Pro 12.9\" (2048×2732)"
        case .ipadPro11M4: return "iPad Pro 11\" M4 (1488×2266)"
        case .ipadPro3Gen11: return "iPad Pro 11\" (1668×2388)"
        case .ipad105: return "iPad 10.5\" (1668×2224)"
        case .ipad97: return "iPad 9.7\" (1536×2048)"
        case .desktop: return "Mac Desktop"
        case .watchUltra: return "Apple Watch Ultra"
        case .watchSeries7: return "Apple Watch Series 7+"
        case .watchSeries4: return "Apple Watch Series 4-6"
        case .watchSeries3: return "Apple Watch Series 3"
        case .appleTV: return "Apple TV"
        case .visionPro: return "Apple Vision Pro"
        }
    }

    /// Groups exposed in the UI picker. Hides categories not targeted by the app (watch/TV/vision)
    /// unless the user explicitly needs them.
    static let userSelectableCases: [ASCDisplayType] = [
        .iphone69, .iphone67, .iphone65, .iphone63, .iphone61, .iphone58, .iphone55, .iphone47,
        .ipadPro129M4, .ipadPro3Gen129, .ipadPro11M4, .ipadPro3Gen11, .ipad105, .ipad97,
        .desktop
    ]

    /// Portrait (short × long) pixel pairs accepted by ASC for this display type.
    /// Desktop is landscape-only. Empty for display types the app doesn't target (watch/TV/vision).
    var acceptedPortraitSizes: [(Int, Int)] {
        switch self {
        case .iphone69: return [(1320, 2868)]
        case .iphone67: return [(1290, 2796)]
        case .iphone65: return [(1242, 2688), (1284, 2778)]
        case .iphone63: return [(1206, 2622)]
        case .iphone61: return [(1170, 2532), (1179, 2556), (1080, 2340)]
        case .iphone58: return [(1125, 2436)]
        case .iphone55: return [(1242, 2208)]
        case .iphone47: return [(750, 1334)]
        case .iphone40: return [(640, 1096), (640, 960)]
        case .iphone35: return [(640, 920), (640, 960)]
        case .ipadPro129M4: return [(2064, 2752)]
        case .ipadPro3Gen129: return [(2048, 2732)]
        case .ipadPro11M4: return [(1488, 2266)]
        case .ipadPro3Gen11: return [(1668, 2388), (1668, 2420), (1640, 2360)]
        case .ipad105: return [(1668, 2224)]
        case .ipad97: return [(1536, 2048)]
        case .desktop: return [(2880, 1800), (2560, 1600), (1440, 900), (1280, 800)]
        default: return []
        }
    }

    var acceptedSizeDescription: String {
        let sizes = acceptedPortraitSizes.map { "\($0.0)×\($0.1)" }
        guard !sizes.isEmpty else { return "No upload sizes listed for this display type." }
        if self == .desktop {
            return sizes.joined(separator: ", ") + " landscape only"
        }
        return sizes.joined(separator: ", ") + " portrait or landscape"
    }

    /// True if the given (width, height) matches an ASC-valid size for this display type.
    /// Phone and tablet entries accept either orientation; desktop entries are landscape-only.
    func accepts(width: CGFloat, height: CGFloat) -> Bool {
        let w = Int(width.rounded())
        let h = Int(height.rounded())
        return acceptedPortraitSizes.contains { pair in
            if self == .desktop {
                return pair.0 == w && pair.1 == h
            }
            return (pair.0 == w && pair.1 == h) || (pair.1 == w && pair.0 == h)
        }
    }

    /// Best-match for the given portrait-or-landscape pixel dimensions.
    /// Limited to `userSelectableCases` so an auto-detected value is always representable in the picker.
    static func detect(width: CGFloat, height: CGFloat) -> ASCDisplayType? {
        ASCDisplayType.userSelectableCases.first { $0.accepts(width: width, height: height) }
    }
}
