import Foundation

/// `ASCScreenshotSyncPlan.sets` grouped for review: version → source row (device) → locale, with
/// the counts each header shows.
///
/// A realistic plan is 90–250 sets — versions × rows × up to 30 locales — and every set repeats its
/// version label and display type. Grouping states those once; the counts are aggregated here, when
/// the plan changes, rather than re-derived by every body pass (same reasoning as
/// `ASCUploadPlanEntries`).
struct ASCScreenshotReviewOutline {
    let versions: [ASCScreenshotReviewVersionSection]
    let changedCount: Int
    let unchangedCount: Int
    let blockedCount: Int

    static let empty = ASCScreenshotReviewOutline(sets: [])

    init(sets: [ASCScreenshotSetDiff]) {
        self.versions = Self.versionSections(from: sets)
        self.changedCount = sets.count { $0.isChanged }
        self.unchangedCount = sets.count { !$0.isChanged }
        self.blockedCount = sets.count { !$0.canApply }
    }

    /// `sets` arrives ordered version → row → locale (that is the order `buildPlan` generates it
    /// in), so grouping by first-seen key preserves it without sorting.
    private static func versionSections(from sets: [ASCScreenshotSetDiff]) -> [ASCScreenshotReviewVersionSection] {
        grouped(sets, by: \.versionId).map { versionId, versionSets in
            ASCScreenshotReviewVersionSection(
                id: versionId,
                versionLabel: versionSets.first?.versionLabel ?? "",
                devices: deviceGroups(from: versionSets)
            )
        }
    }

    private static func deviceGroups(from sets: [ASCScreenshotSetDiff]) -> [ASCScreenshotReviewDeviceGroup] {
        grouped(sets, by: { "\($0.versionId)|\($0.rowId.uuidString)" }).map { key, groupSets in
            ASCScreenshotReviewDeviceGroup(id: key, sets: groupSets)
        }
    }

    private static func grouped(
        _ sets: [ASCScreenshotSetDiff],
        by key: (ASCScreenshotSetDiff) -> String
    ) -> [(String, [ASCScreenshotSetDiff])] {
        var order: [String] = []
        var grouped: [String: [ASCScreenshotSetDiff]] = [:]
        for set in sets {
            let key = key(set)
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(set)
        }
        return order.compactMap { key in
            guard let sets = grouped[key], !sets.isEmpty else { return nil }
            return (key, sets)
        }
    }
}

/// What the included sets add up to — shown live in the review toolbar and restated in the
/// confirmation dialog, from one aggregation instead of two.
struct ASCScreenshotSelectionTotals {
    let setCount: Int
    let uploads: Int
    let removals: Int
    let moves: Int
    let preserved: Int
    let capacityFirstDeletions: Int

    init(sets: [ASCScreenshotSetDiff]) {
        self.setCount = sets.count
        self.uploads = sets.reduce(0) { $0 + $1.uploadCount }
        self.removals = sets.reduce(0) { $0 + $1.removalCount }
        self.moves = sets.reduce(0) { $0 + $1.moveCount }
        self.preserved = sets.reduce(0) { $0 + $1.unchangedCount }
        self.capacityFirstDeletions = sets.reduce(0) { $0 + $1.capacityFirstDeletionCount }
    }
}

struct ASCScreenshotReviewVersionSection: Identifiable {
    let id: String
    let versionLabel: String
    let devices: [ASCScreenshotReviewDeviceGroup]

    var setCount: Int { devices.reduce(0) { $0 + $1.sets.count } }
    var changedCount: Int { devices.reduce(0) { $0 + $1.changedCount } }
    var blockedCount: Int { devices.reduce(0) { $0 + $1.blockedCount } }
}

/// One source row's sets for one version — the row maps to exactly one display type, so this is
/// also "everything going to iPhone 6.9\" for version 1.4", one entry per locale.
struct ASCScreenshotReviewDeviceGroup: Identifiable {
    let id: String
    let sets: [ASCScreenshotSetDiff]
    let changedCount: Int
    let blockedCount: Int
    let uploadCount: Int
    let removalCount: Int
    let moveCount: Int

    let rowLabel: String
    let displayTypeLabel: String
    let displayTypeRawValue: String

    init(id: String, sets: [ASCScreenshotSetDiff]) {
        self.id = id
        self.sets = sets
        self.changedCount = sets.count { $0.isChanged }
        self.blockedCount = sets.count { !$0.canApply }
        self.uploadCount = sets.reduce(0) { $0 + $1.uploadCount }
        self.removalCount = sets.reduce(0) { $0 + $1.removalCount }
        self.moveCount = sets.reduce(0) { $0 + $1.moveCount }
        self.rowLabel = sets.first?.rowLabel ?? ""
        self.displayTypeLabel = sets.first?.displayType.label ?? ""
        self.displayTypeRawValue = sets.first?.displayType.appStoreConnectValue ?? ""
    }
}
