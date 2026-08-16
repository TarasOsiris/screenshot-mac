import Foundation

// Plan types describing what the Google Play upload will do. They live in the service layer
// so the validator and its tests do not depend on the SwiftUI upload view.

struct GPRowPlan: Identifiable {
    let id: UUID
    var rowLabel: String
    var rowSize: CGSize
    var templateCount: Int
    var isEnabled: Bool
    var detectedImageType: GPImageType
    var selectedImageType: GPImageType
    var localeTargets: [GPLocaleTarget]
    var inferredStorePlatform: StorePlatform?
}

struct GPLocaleTarget: Identifiable {
    let id = UUID()
    var appLocaleCode: String
    var appLocaleLabel: String
    var playLanguageCode: String
    var isEnabled: Bool
}
