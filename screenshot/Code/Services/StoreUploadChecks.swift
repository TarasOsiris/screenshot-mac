import Foundation

/// One row's claim on a destination slot in the store. Two claims on the same key would overwrite
/// each other's screenshots — whether they come from two rows or from two locales inside one row.
nonisolated struct UploadTargetClaim {
    let rowId: UUID
    let rowName: String
    /// What inside the row makes the claim, named the way the user sees it ("English (US)").
    let targetLabel: String
    /// Store-specific destination identity: "\(localizationId)|\(displayType)" for Apple,
    /// "\(playLanguageCode)|\(imageType)" for Play.
    let key: String
    /// The destination named the way the user sees it in the row ("en-US").
    let slotLabel: String
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

    /// Two kinds of collision, told apart by row *id* — a row whose own locales collapse onto one
    /// store slot (several project languages mapping to one store language) cannot be fixed by
    /// disabling a row, so it must not be reported as if another row were involved.
    ///
    /// `sameRow` fires once per colliding slot, naming every locale that lands on it. `otherRow`
    /// fires once per colliding *partner row*, not per shared key — a pair of rows that collide
    /// across twelve locales must report once, not twelve times. Claims are consumed in order and
    /// the first row to claim a key owns it.
    static func collisionIssues(
        _ claims: [UploadTargetClaim],
        sameRow: (_ rowName: String, _ targetLabels: [String], _ slotLabel: String) -> UploadIssue,
        otherRow: (_ rowName: String, _ partnerRowName: String) -> UploadIssue
    ) -> [UploadIssue] {
        struct GroupKey: Hashable {
            let rowId: UUID
            let key: String
        }

        var order: [GroupKey] = []
        var groups: [GroupKey: [UploadTargetClaim]] = [:]
        for claim in claims {
            let group = GroupKey(rowId: claim.rowId, key: claim.key)
            if groups[group] == nil { order.append(group) }
            groups[group, default: []].append(claim)
        }

        var issues: [UploadIssue] = []
        var owners: [String: (rowId: UUID, rowName: String)] = [:]
        var reportedPartnersByRow: [UUID: Set<UUID>] = [:]

        for group in order {
            guard let claimants = groups[group], let first = claimants.first else { continue }

            if claimants.count > 1 {
                issues.append(sameRow(first.rowName, claimants.map(\.targetLabel), first.slotLabel))
            }

            guard let owner = owners[group.key] else {
                owners[group.key] = (first.rowId, first.rowName)
                continue
            }
            if reportedPartnersByRow[first.rowId, default: []].insert(owner.rowId).inserted {
                issues.append(otherRow(first.rowName, owner.rowName))
            }
        }
        return issues
    }
}
