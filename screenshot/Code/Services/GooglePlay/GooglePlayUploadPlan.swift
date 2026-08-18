import Foundation

// Plan types describing what the Google Play upload will do. They live in the service layer
// so the validator and its tests do not depend on the SwiftUI upload view.

typealias GPRowPlan = StoreRowPlan<GPImageType, GPLocaleTarget>

nonisolated struct GPLocaleTarget: Identifiable {
    let id = UUID()
    var appLocaleCode: String
    var appLocaleLabel: String
    var playLanguageCode: String
    var isEnabled: Bool
}
