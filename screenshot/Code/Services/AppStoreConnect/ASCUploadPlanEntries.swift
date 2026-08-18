import Foundation

/// The upload plan fanned out to one entry per (destination, row, locale), with the groupings and
/// counts the plan screen shows.
///
/// This was five computed properties on the view — a triple-nested flatMap re-derived by each of
/// them, so a single body pass rebuilt it four times, plus a sixth site that recomputed the same
/// aggregates inline. Building it once, when the plan changes, is what `ASCUploadFlowModel`'s
/// `updateDestinationPlans` is for.
struct ASCUploadPlanEntries {
    let all: [ASCUploadPlanEntry]
    let selected: [ASCUploadPlanEntry]
    let skipped: [ASCUploadPlanEntry]
    /// Grouped by source row, so the constant row/display-type details render once instead of
    /// repeating under every locale.
    let rowGroups: [ASCUploadRowGroup]
    let localeGroups: [ASCUploadLocaleGroup]
    let versionCount: Int
    let localeCount: Int
    let screenshotCount: Int

    static let empty = ASCUploadPlanEntries(destinations: [])

    init(destinations: [ASCDestinationPlan]) {
        let all = Self.entries(from: destinations)
        let selected = all.filter(\.isSelected)
        self.all = all
        self.selected = selected
        self.skipped = all.filter { !$0.isSelected }
        self.rowGroups = Self.rowGroups(from: selected)
        self.localeGroups = Self.localeGroups(from: selected)
        self.versionCount = Set(selected.map(\.destinationId)).count
        self.localeCount = Set(selected.map { "\($0.destinationId)|\($0.appStoreLocaleCode ?? $0.projectLocaleCode)" }).count
        self.screenshotCount = selected.reduce(0) { $0 + $1.screenshotCount }
    }

    private static func entries(from destinations: [ASCDestinationPlan]) -> [ASCUploadPlanEntry] {
            destinations.flatMap { destination -> [ASCUploadPlanEntry] in
                destination.rowPlans.flatMap { plan -> [ASCUploadPlanEntry] in
                    guard plan.isEnabled else { return [] }
                    let rowLabel = plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel
                    let sourceSizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"
                    let displayTypeLabel = plan.selectedAssetType?.label ?? String(localized: "No display type selected")
                    let displayTypeRawValue = plan.selectedAssetType?.appStoreConnectValue ?? "none"

                    return plan.localeTargets.flatMap { target -> [ASCUploadPlanEntry] in
                        func entry(idSuffix: String, appStoreLocaleCode: String?, isSelected: Bool, skipReason: String?) -> ASCUploadPlanEntry {
                            ASCUploadPlanEntry(
                                id: "\(destination.id)-\(plan.id.uuidString)-\(target.id.uuidString)\(idSuffix)",
                                destinationId: destination.id,
                                destinationLabel: destination.title,
                                destinationPlatform: destination.version.attributes.ascPlatform,
                                rowPlanId: plan.id,
                                rowLabel: rowLabel,
                                sourceSizeLabel: sourceSizeLabel,
                                displayTypeLabel: displayTypeLabel,
                                displayTypeRawValue: displayTypeRawValue,
                                projectLocaleLabel: target.appLocaleLabel,
                                projectLocaleCode: target.appLocaleCode,
                                appStoreLocaleCode: appStoreLocaleCode,
                                templateCount: plan.templateCount,
                                isSelected: isSelected,
                                skipReason: skipReason
                            )
                        }

                        let selectedCandidates = target.selectedCandidates
                        if target.isEnabled, plan.selectedAssetType != nil, !selectedCandidates.isEmpty {
                            // One entry per App Store destination this locale fans out to.
                            return selectedCandidates.map { candidate in
                                entry(idSuffix: "-\(candidate.id)", appStoreLocaleCode: candidate.attributes.locale, isSelected: true, skipReason: nil)
                            }
                        }

                        let skipReason: String
                        if target.candidates.isEmpty {
                            skipReason = String(localized: "No matching App Store locale")
                        } else if !target.isEnabled {
                            skipReason = String(localized: "Unchecked")
                        } else if plan.selectedAssetType == nil {
                            skipReason = String(localized: "No display type selected")
                        } else {
                            skipReason = String(localized: "No App Store locale selected")
                        }
                        return [entry(idSuffix: "", appStoreLocaleCode: nil, isSelected: false, skipReason: skipReason)]
                    }
                }
            }
    }

    /// Group already-filtered entries by App Store (or project) locale. Takes the entries as a
    /// parameter so callers that already computed `uploadPlanEntries` don't recompute it.
    private static func localeGroups(from entries: [ASCUploadPlanEntry]) -> [ASCUploadLocaleGroup] {
        let grouped = Dictionary(grouping: entries) { entry in
            "\(entry.destinationId)|\(entry.appStoreLocaleCode ?? entry.projectLocaleCode)"
        }
        return grouped.keys.sorted().map { code in
            let groupEntries = grouped[code] ?? []
            let label = groupEntries.first.map { "\($0.destinationLabel) · \($0.projectLocaleLabel) -> \($0.appStoreLocaleCode ?? $0.projectLocaleCode)" } ?? code
            return ASCUploadLocaleGroup(id: code, label: label, entries: groupEntries)
        }
    }

    /// Group entries by source row, preserving the row order in which they were generated, so the
    /// constant row/display-type details render once instead of repeating under every locale.
    private static func rowGroups(from entries: [ASCUploadPlanEntry]) -> [ASCUploadRowGroup] {
        var order: [String] = []
        var grouped: [String: [ASCUploadPlanEntry]] = [:]
        for entry in entries {
            let key = "\(entry.destinationId)|\(entry.rowPlanId.uuidString)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let groupEntries = grouped[key], let first = groupEntries.first else { return nil }
            return ASCUploadRowGroup(
                id: key,
                destinationLabel: first.destinationLabel,
                destinationPlatform: first.destinationPlatform,
                rowLabel: first.rowLabel,
                sourceSizeLabel: first.sourceSizeLabel,
                displayTypeLabel: first.displayTypeLabel,
                displayTypeRawValue: first.displayTypeRawValue,
                templateCount: first.templateCount,
                entries: groupEntries
            )
        }
    }
}
