import Foundation

// Plan types describing what the Google Play upload will do. They live in the service layer
// so the validator and its tests do not depend on the SwiftUI upload view.

typealias GPRowPlan = StoreRowPlan<GPImageType, GPLocaleTarget>

/// One project locale's place in a Play upload. `playLanguageCode` is nil when Play has no
/// listing language for the project code, which is a permanent fact about the locale rather than
/// something the user can toggle away.
nonisolated struct GPLocaleTarget: LocaleUploadTarget {
    let id = UUID()
    var appLocaleCode: String
    var appLocaleLabel: String
    var playLanguageCode: String?
    var isEnabled: Bool

    var isToggleable: Bool { playLanguageCode != nil }
}
