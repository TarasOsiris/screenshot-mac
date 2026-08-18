import Foundation

/// One row's claim on a destination slot in the store. Two rows claiming the same key would
/// overwrite each other's screenshots.
nonisolated struct UploadTargetClaim {
    let rowName: String
    /// Store-specific: "\(localizationId)|\(displayType)" for Apple,
    /// "\(playLanguageCode)|\(imageType)" for Play.
    let key: String

    init(rowName: String, key: String) {
        self.rowName = rowName
        self.key = key
    }
}

/// The parts of upload validation that are genuinely the same for both stores.
///
/// Deliberately *not* a shared validator: the limits, severities, message wording, demo-mode
/// downgrade policy and size rules are real per-store domain knowledge and stay in
/// `AppStoreConnectUploadValidator` / `GooglePlayUploadValidator`. What is shared is the row
/// naming, the two early exits, and the collision algorithm — which Play relies on but never
/// tested.
nonisolated enum StoreUploadChecks {
    /// Rows may be unlabelled; every message still needs something to call them.
    static func rowName(_ label: String) -> String {
        label.isEmpty ? "Row" : label
    }

    static func sizeLabel(_ size: CGSize) -> String {
        "\(Int(size.width))×\(Int(size.height))"
    }

    /// The blocking issue when there is nothing to upload, or nil when the plans are usable.
    /// Mirrors the two early exits both validators run before any per-row work.
    static func emptyPlansIssue(planCount: Int, enabledCount: Int) -> UploadIssue? {
        if planCount == 0 {
            return UploadIssue(
                severity: .error,
                message: "This project has no rows to upload.",
                hint: "Add a row in the editor before running the upload."
            )
        }
        if enabledCount == 0 {
            return UploadIssue(severity: .error, message: "Enable at least one row to upload.")
        }
        return nil
    }

    /// One issue per colliding *partner row*, not per shared key — a pair of rows that collide
    /// across twelve locales must report once, not twelve times. Claims are consumed in order and
    /// the first row to claim a key owns it.
    static func collisionIssues(
        _ claims: [UploadTargetClaim],
        issue: (_ rowName: String, _ partnerRowName: String) -> UploadIssue
    ) -> [UploadIssue] {
        var issues: [UploadIssue] = []
        var owners: [String: String] = [:]
        var reportedPartnersByRow: [String: Set<String>] = [:]

        for claim in claims {
            guard let owner = owners[claim.key] else {
                owners[claim.key] = claim.rowName
                continue
            }
            // No same-name guard: rows are identified by label, and two *unlabelled* rows both
            // read as "Row" — suppressing those would hide a real collision.
            if reportedPartnersByRow[claim.rowName, default: []].insert(owner).inserted {
                issues.append(issue(claim.rowName, owner))
            }
        }
        return issues
    }
}
