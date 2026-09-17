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

/// Whether the package name in the field has been confirmed to be one this service account can
/// edit. Play has no app list to pick from, so this is what stands in for App Store Connect's
/// app-selection step — without it a typo or a missing permission only surfaces mid-upload.
enum GPPackageVerification: Equatable {
    case unverified
    case verifying
    case verified(String)
    case failed(String)

    var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }
}
