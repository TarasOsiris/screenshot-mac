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

nonisolated struct ASCLocaleTarget: Identifiable {
    let id = UUID()
    var appLocaleCode: String
    var appLocaleLabel: String
    var selectedASCLocalizationIds: Set<String>
    var candidates: [ASCAppStoreVersionLocalization]
    var isEnabled: Bool

    var selectedCandidates: [ASCAppStoreVersionLocalization] {
        candidates.filter { selectedASCLocalizationIds.contains($0.id) }
    }
}
