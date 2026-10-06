import Foundation

/// Apple requires iPhone Duo screenshots from April 2027; until then a version without them only warns.
enum ASCDuoReadiness {
    static func issue(destination: ASCDestinationPlan, remoteCounts: [String: [String: Int]]) -> UploadIssue? {
        guard destination.version.attributes.ascPlatform == .ios else { return nil }
        let plannedTypes = destination.rowPlans.filter(\.isEnabled).compactMap(\.selectedAssetType)
        guard plannedTypes.contains(where: { $0.family == .iphone }),
              !plannedTypes.contains(.iphoneDuo) else { return nil }
        let duoKey = ASCDisplayType.iphoneDuo.appStoreConnectValue
        let knownCounts = destination.localizations.compactMap { remoteCounts[$0.id] }
        // Counts that failed to load prove nothing, so stay quiet rather than warn about sets that may exist.
        guard !knownCounts.isEmpty, !knownCounts.contains(where: { ($0[duoKey] ?? 0) > 0 }) else { return nil }
        return UploadIssue(
            severity: .warning,
            message: String(localized: "This version has no iPhone Duo screenshots. Starting April 2027, App Store submissions must include them."),
            hint: String(localized: "Add a row at an iPhone Duo size — 2007×2853 for the inner display or 1398×2034 for the outer display.")
        )
    }
}
