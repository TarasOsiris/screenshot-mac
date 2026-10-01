import Foundation

// Plan types describing what the App Store Connect upload will do. They live in the service
// layer so the validators and their tests do not depend on the SwiftUI upload view.

typealias ASCRowPlan = StoreRowPlan<ASCDisplayType?, ASCLocaleTarget>

nonisolated struct ASCDestinationPlan: Identifiable {
    let id: String
    var version: ASCAppStoreVersion
    var localizations: [ASCAppStoreVersionLocalization]
    var rowPlans: [ASCRowPlan]

    var title: String {
        let versionText = String(localized: "Version \(version.attributes.versionString)")
        if let platform = version.attributes.displayPlatform {
            return "\(platform) · \(versionText)"
        }
        return versionText
    }

    var subtitle: String {
        version.attributes.displayState
    }
}

nonisolated struct ASCLocaleTarget: LocaleUploadTarget {
    let id = UUID()
    var appLocaleCode: String
    var appLocaleLabel: String
    var selectedASCLocalizationIds: Set<String>
    var candidates: [ASCAppStoreVersionLocalization]
    var isEnabled: Bool

    var isToggleable: Bool { !candidates.isEmpty }

    var selectedCandidates: [ASCAppStoreVersionLocalization] {
        candidates.filter { selectedASCLocalizationIds.contains($0.id) }
    }
}

/// What App Store Connect already holds for one localization, relative to the display type a row
/// uploads as.
enum ASCRemoteScreenshotStatus: Equatable {
    /// No screenshots in any display type.
    case empty
    /// Screenshots exist, but none of this display type.
    case missingForDisplayType
    case present(Int)

    /// Nil when either side isn't known yet, so nothing is claimed about the locale.
    static func resolve(counts: [String: Int]?, displayType: ASCDisplayType?) -> Self? {
        guard let counts, let displayType else { return nil }
        if let count = counts[displayType.appStoreConnectValue], count > 0 { return .present(count) }
        return counts.values.contains { $0 > 0 } ? .missingForDisplayType : .empty
    }
}
