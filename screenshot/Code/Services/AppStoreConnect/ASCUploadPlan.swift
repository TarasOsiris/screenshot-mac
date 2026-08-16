import Foundation

// Plan types describing what the App Store Connect upload will do. They live in the service
// layer so the validators and their tests do not depend on the SwiftUI upload view.

nonisolated struct ASCRowPlan: Identifiable {
    let id: UUID
    var rowLabel: String
    var rowSize: CGSize
    var templateCount: Int
    var isEnabled: Bool
    var detectedDisplayType: ASCDisplayType?
    var selectedDisplayType: ASCDisplayType?
    var localeTargets: [ASCLocaleTarget]
    var inferredStorePlatform: StorePlatform?
}

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
