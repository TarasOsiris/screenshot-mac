import Foundation

/// Apple requires one Apple Watch screenshot size across every localization of an app.
enum ASCWatchSizeConsistency {
    /// Keyed on pixel size, not display type: Ultra's two sizes share `APP_WATCH_ULTRA` but still count as two.
    static func sizeKey(_ displayType: ASCDisplayType?, size: CGSize) -> String? {
        displayType?.family == .watch ? StoreUploadChecks.sizeLabel(size) : nil
    }

    static func mixedPlanIssue(plans: [ASCRowPlan]) -> UploadIssue? {
        let plannedSizes = Set(plans.filter(\.isEnabled).compactMap { sizeKey($0.selectedAssetType, size: $0.rowSize) })
        guard plannedSizes.count > 1 else { return nil }
        return UploadIssue(
            severity: .error,
            message: String(localized: "This upload mixes Apple Watch sizes (\(plannedSizes.sorted().formatted(.list(type: .and)))). App Store Connect requires one Apple Watch size across all localizations."),
            hint: String(localized: "Resize every Apple Watch row to the same size, or turn off the extra rows."),
            demoDowngradable: true
        )
    }

    /// Sets this upload doesn't replace stay on the version, so a different size already there still conflicts.
    static func remoteConflictIssue(destination: ASCDestinationPlan, remoteCounts: [String: [String: Int]]) -> UploadIssue? {
        let plannedTypes = Set(destination.rowPlans.filter(\.isEnabled).compactMap(\.selectedAssetType).filter { $0.family == .watch })
        guard plannedTypes.count == 1 else { return nil }
        // Watch types upload under their own raw value, so the remote set key maps straight back.
        let remoteTypes = Set(destination.localizations.flatMap { localization in
            (remoteCounts[localization.id] ?? [:]).compactMap { value, count in
                count > 0 ? ASCDisplayType(rawValue: value).flatMap { $0.family == .watch ? $0 : nil } : nil
            }
        })
        let existingTypes = remoteTypes.subtracting(plannedTypes)
        guard !existingTypes.isEmpty else { return nil }
        let names = ASCDisplayType.allCases.filter(plannedTypes.union(existingTypes).contains).map(\.shortLabel).formatted(.list(type: .and))
        return UploadIssue(
            severity: .warning,
            message: String(localized: "This version would have screenshots for more than one Apple Watch size (\(names)). App Store Connect requires one Apple Watch size across all localizations."),
            hint: String(localized: "Delete the other Apple Watch size's screenshots in App Store Connect, or resize your Apple Watch rows to match them.")
        )
    }
}
