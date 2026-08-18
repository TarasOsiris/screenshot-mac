import Foundation

/// What a Google Play upload actually did, and the wizard's screens in order.
struct GPUploadSummary {
    let totalScreenshots: Int
    let languageCount: Int
    let packageName: String
    /// What actually happened on commit (the draft flag may be rejected → sent to review).
    let sentForReview: Bool
}

enum GPUploadStep: Hashable {
    case enteringPackage
    case configuringPlan
    case uploading
    case done
}
