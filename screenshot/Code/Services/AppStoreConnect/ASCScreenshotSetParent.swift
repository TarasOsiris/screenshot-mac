import Foundation

/// What a screenshot set hangs off — the only place a product page and an experiment treatment differ.
nonisolated enum ASCScreenshotSetParentKind: String, Hashable, Sendable {
    /// The product page itself (`appStoreVersionLocalizations`).
    case versionLocalization
    /// A product page experiment treatment (`appStoreVersionExperimentTreatmentLocalizations`).
    case treatmentLocalization

    var resourceType: String {
        switch self {
        case .versionLocalization: "appStoreVersionLocalizations"
        case .treatmentLocalization: "appStoreVersionExperimentTreatmentLocalizations"
        }
    }

    /// The to-one relationship key on an `appScreenshotSets` create request.
    var relationshipKey: String {
        switch self {
        case .versionLocalization: "appStoreVersionLocalization"
        case .treatmentLocalization: "appStoreVersionExperimentTreatmentLocalization"
        }
    }
}

nonisolated struct ASCScreenshotSetParent: Hashable, Sendable {
    let kind: ASCScreenshotSetParentKind
    let id: String

    static func versionLocalization(_ id: String) -> Self { Self(kind: .versionLocalization, id: id) }
    static func treatmentLocalization(_ id: String) -> Self { Self(kind: .treatmentLocalization, id: id) }

    var screenshotSetsPath: String { "/v1/\(kind.resourceType)/\(id)/appScreenshotSets" }
}
