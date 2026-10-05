import Foundation

/// Per-row cross-locale screenshot-count warnings for what a version will hold once the upload lands.
enum ASCListingConsistency {
    static func issues(
        row: ASCRowPlan,
        in destination: ASCDestinationPlan,
        remoteCounts: [String: [String: Int]],
        primaryLocale: String?
    ) -> [UploadIssue] {
        guard row.isEnabled, row.templateCount > 0, let displayType = row.selectedAssetType else { return [] }
        let targetedIds = row.uploadedLocalizationIds
        let key = displayType.appStoreConnectValue
        // What the upload's other rows will leave in the localizations they target.
        var planned: [String: [String: Int]] = [:]
        for other in destination.rowPlans where other.id != row.id && other.isEnabled {
            guard let otherKey = other.selectedAssetType?.appStoreConnectValue else { continue }
            for id in other.uploadedLocalizationIds {
                planned[id, default: [:]][otherKey] = other.templateCount
            }
        }
        // Offering these in the Fix would make two rows write one screenshot set.
        let claimedByOtherRows = Set(planned.filter { $0.value[key] != nil }.keys)
        let familyKeys = Set(ASCDisplayType.allCases.filter { $0.family == displayType.family }.map(\.appStoreConnectValue))
        let primary = primaryLocale?.lowercased()

        let known = destination.localizations
            .filter { targetedIds.contains($0.id) || remoteCounts[$0.id] != nil || planned[$0.id]?[key] != nil }
            .sorted { $0.attributes.locale < $1.attributes.locale }
        guard known.count >= 2 else { return [] }

        var counted: [(localization: ASCAppStoreVersionLocalization, count: Int)] = []
        var missing: [(localization: ASCAppStoreVersionLocalization, hasOtherSize: Bool)] = []
        var primaryMissing: ASCAppStoreVersionLocalization?
        for localization in known {
            if targetedIds.contains(localization.id) {
                counted.append((localization, row.templateCount))
                continue
            }
            let afterUpload = (remoteCounts[localization.id] ?? [:]).merging(planned[localization.id] ?? [:]) { $1 }
            // Only this device family counts: an iPad set doesn't stop iPhones falling back.
            switch StoreRemoteScreenshotStatus.resolve(counts: afterUpload.filter { familyKeys.contains($0.key) }, assetKey: key) {
            case .present(let count):
                counted.append((localization, count))
            case .missingForThisType:
                missing.append((localization, true))
            case .empty, nil:
                if localization.attributes.locale.lowercased() == primary {
                    primaryMissing = localization
                } else {
                    missing.append((localization, false))
                }
            }
        }
        // Without a primary set there is nothing to fall back to, so every gap is just a gap.
        let fallingBack = primaryMissing == nil ? missing.filter { !$0.hasOtherSize }.map(\.localization) : []
        let missingSize = primaryMissing == nil ? missing.filter(\.hasOtherSize).map(\.localization) : missing.map(\.localization)

        let type = displayType.shortLabel
        let issue = { (message: String, flagged: [ASCAppStoreVersionLocalization]) in
            makeIssue(message: message, flagged: flagged.filter { !claimedByOtherRows.contains($0.id) }, row: row, destinationId: destination.id)
        }
        var issues: [UploadIssue] = []

        if let reference = referenceCount(counted.map(\.count), preferring: row.templateCount),
           let outlier = counted.first(where: { $0.count != reference }) {
            let outliers = counted.filter { $0.count != reference }
            let message: String
            if outliers.count == 1, counted.count == known.count {
                message = String(inflecting: "\(outlier.localization.attributes.locale) has ^[\(outlier.count) \(type) screenshot](inflect: true) where every other locale has \(reference).")
            } else {
                let list = outliers.map { String(localized: "\($0.localization.attributes.locale) has \($0.count)") }.formatted(.list(type: .and))
                message = String(inflecting: "Most locales have ^[\(reference) \(type) screenshot](inflect: true), but \(list).")
            }
            issues.append(issue(message, outliers.map(\.localization)))
        }

        if let primaryMissing {
            issues.append(issue(
                String(localized: "\(primaryMissing.attributes.locale), the primary language, has no \(type) set, so locales without one have nothing to fall back to."),
                [primaryMissing]
            ))
        }

        if !fallingBack.isEmpty {
            let language = primaryLocale.map(LocaleDefinition.displayName(forCode:)) ?? String(localized: "the primary language")
            let list = fallingBack.map(\.attributes.locale).formatted(.list(type: .and))
            let message = fallingBack.count == 1
                ? String(localized: "\(list) has no \(type) set, so it falls back to \(language).")
                : String(localized: "\(list) have no \(type) set, so they fall back to \(language).")
            issues.append(issue(message, fallingBack))
        }

        if !missingSize.isEmpty {
            let list = missingSize.map(\.attributes.locale).formatted(.list(type: .and))
            let message = missingSize.count == 1
                ? String(localized: "\(list) has no \(type) set.")
                : String(localized: "\(list) have no \(type) set.")
            issues.append(issue(message, missingSize))
        }

        return issues
    }

    /// The most common count; a tie goes to what this row uploads, then to the larger count.
    static func referenceCount(_ counts: [Int], preferring preferred: Int) -> Int? {
        let tally = Dictionary(counts.map { ($0, 1) }, uniquingKeysWith: +)
        guard let top = tally.values.max() else { return nil }
        let tied = tally.filter { $0.value == top }.map(\.key)
        return tied.contains(preferred) ? preferred : tied.max()
    }

    /// Flagged locales this row can reach become the Fix; the rest get a "Not in this project" hint.
    private static func makeIssue(
        message: String,
        flagged: [ASCAppStoreVersionLocalization],
        row: ASCRowPlan,
        destinationId: String
    ) -> UploadIssue {
        let flaggedIds = Set(flagged.map(\.id))
        let reachable = row.localeTargets.filter { target in
            target.candidates.contains { flaggedIds.contains($0.id) }
        }
        let matchedIds = Set(reachable.flatMap(\.candidates).map(\.id))
        let unmatched = flagged.filter { !matchedIds.contains($0.id) }.map(\.attributes.locale)

        var hints: [String] = []
        let fixable = reachable.map(\.appLocaleCode)
        if !fixable.isEmpty {
            hints.append(String(localized: "Fix uploads this row to \(fixable.formatted(.list(type: .and))) too."))
        }
        if !unmatched.isEmpty {
            hints.append(String(localized: "Not in this project: \(unmatched.formatted(.list(type: .and))). Add those languages to upload this row to them."))
        }
        return UploadIssue(
            severity: .warning,
            message: message,
            hint: hints.isEmpty ? nil : hints.joined(separator: " "),
            fix: fixable.isEmpty ? nil : UploadIssueFix(.selectMatchingStoreLocales, destinationId: destinationId, rowId: row.id, appLocaleCodes: fixable)
        )
    }
}
