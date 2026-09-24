import Foundation

/// What a Google Play upload actually did, and the wizard's screens in order.
struct GPUploadSummary {
    let totalScreenshots: Int
    let languageCount: Int
    let packageName: String
    /// What actually happened on commit (the draft flag may be rejected → sent to review).
    let sentForReview: Bool

    var countsText: String {
        switch (totalScreenshots == 1, languageCount == 1) {
        case (true, true):
            String(localized: "1 screenshot across 1 language")
        case (true, false):
            String(localized: "1 screenshot across \(languageCount) languages")
        case (false, true):
            String(localized: "\(totalScreenshots) screenshots across 1 language")
        case (false, false):
            String(localized: "\(totalScreenshots) screenshots across \(languageCount) languages")
        }
    }
}

/// Counted from the upload targets rather than the row plans, so the preview can't disagree with
/// what uploads once duplicate Play languages are collapsed.
struct GPUploadCounts: Equatable {
    let rows: Int
    let screenshots: Int
    let languages: Int

    init(targets: [GPUploadTarget]) {
        rows = targets.count
        screenshots = targets.reduce(0) { $0 + $1.templateCount * $1.languages.count }
        languages = Set(targets.flatMap { $0.languages.map(\.playCode) }).count
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
