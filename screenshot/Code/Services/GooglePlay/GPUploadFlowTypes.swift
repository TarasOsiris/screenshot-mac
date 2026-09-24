import Foundation

/// What a Google Play upload actually did, and the wizard's screens in order.
struct GPUploadSummary {
    let counts: GPUploadCounts
    let packageName: String
    /// What actually happened on commit (the draft flag may be rejected → sent to review).
    let sentForReview: Bool
}

/// What a plan uploads once duplicate Play languages are collapsed, so the preview can't promise
/// more than the upload sends.
struct GPUploadCounts: Equatable {
    var rows = 0
    var screenshots = 0
    var languages = 0

    var text: String {
        switch (screenshots == 1, languages == 1) {
        case (true, true):
            String(localized: "1 screenshot across 1 language")
        case (true, false):
            String(localized: "1 screenshot across \(languages) languages")
        case (false, true):
            String(localized: "\(screenshots) screenshots across 1 language")
        case (false, false):
            String(localized: "\(screenshots) screenshots across \(languages) languages")
        }
    }
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
