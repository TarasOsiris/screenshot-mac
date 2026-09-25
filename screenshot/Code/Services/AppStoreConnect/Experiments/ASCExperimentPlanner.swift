import Foundation

/// One variant's treatment and the treatment localizations its rows upload into.
struct ASCTreatmentTarget {
    let variantId: UUID
    let treatment: ASCExperimentTreatment
    let localizations: [ASCUploadLocalization]
}

/// The pure half of the experiment flow: row → treatment mapping, locale matching, and preflight.
enum ASCExperimentPlanner {

    /// Each variant's App Store rows, grouped in one pass; the Original (nil key) is dropped.
    static func rowsByVariant(_ rows: [ScreenshotRow]) -> [UUID: [ScreenshotRow]] {
        var groups: [UUID: [ScreenshotRow]] = [:]
        for row in rows {
            guard let variantId = row.variantId, row.uploadsToAppStore(from: variantId) else { continue }
            groups[variantId, default: []].append(row)
        }
        return groups
    }

    /// Variants that have at least one row, in document order — each becomes one treatment.
    static func variantsWithRows(_ variants: [ScreenshotVariant], rowsByVariant: [UUID: [ScreenshotRow]]) -> [ScreenshotVariant] {
        variants.filter { rowsByVariant[$0.id] != nil }
    }

    /// Each variant's existing treatment, matched by name; nil means one will be created.
    static func treatmentMatches(
        variants: [ScreenshotVariant],
        existing: [ASCExperimentTreatment]
    ) -> [UUID: ASCExperimentTreatment] {
        var remaining = existing
        var matches: [UUID: ASCExperimentTreatment] = [:]
        for variant in variants {
            let key = variant.name.trimmingCharacters(in: .whitespaces).lowercased()
            guard let index = remaining.firstIndex(where: {
                $0.name.trimmingCharacters(in: .whitespaces).lowercased() == key
            }) else { continue }
            matches[variant.id] = remaining.remove(at: index)
        }
        return matches
    }

    /// Project locale code → App Store locale code, matched the way the regular upload matches them.
    static func localeAssignment(
        projectCodes: [String],
        productPageLocalizations: [ASCAppStoreVersionLocalization]
    ) -> [String: String] {
        let assigned = ASCLocaleMatcher.assign(appCodes: projectCodes, to: productPageLocalizations)
        return assigned.compactMapValues { $0.first?.attributes.locale }
    }

    static func uploadableDisplayType(for row: ScreenshotRow, platform: ASCPlatform) -> ASCDisplayType? {
        guard let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight),
              detected.accepts(platform: platform) else { return nil }
        return detected
    }

    static func issues(
        variants: [ScreenshotVariant],
        rowsByVariant: [UUID: [ScreenshotRow]],
        platform: ASCPlatform,
        experiment: ASCExperiment?,
        existingTreatments: [ASCExperimentTreatment],
        newExperimentName: String,
        enabledLocaleCodes: Set<String>,
        localeAssignment: [String: String]
    ) -> [UploadIssue] {
        var issues: [UploadIssue] = []
        let testable = variantsWithRows(variants, rowsByVariant: rowsByVariant)
        if testable.isEmpty {
            issues.append(UploadIssue(severity: .error, message: String(localized: "Create a variant first: use Duplicate as Variant on a row, then change the copy.")))
        }
        let matched = treatmentMatches(variants: testable, existing: existingTreatments).count
        if existingTreatments.count + testable.count - matched > ASCExperiment.maxTreatments {
            issues.append(UploadIssue(severity: .error, message: String(localized: "An App Store experiment holds at most 3 treatments. Delete a variant or merge two.")))
        }
        if let experiment {
            if !experiment.state.isEditable {
                issues.append(UploadIssue(severity: .error, message: String(localized: "“\(experiment.name)” is \(experiment.statusText.lowercased()) and can no longer be changed. Start a new experiment.")))
            }
        } else if newExperimentName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(UploadIssue(severity: .error, message: String(localized: "Name the new experiment.")))
        }
        if !enabledLocaleCodes.contains(where: { localeAssignment[$0] != nil }) {
            issues.append(UploadIssue(severity: .error, message: String(localized: "Select at least one language that exists on your product page.")))
        }
        for variant in testable {
            let variantRows = rowsByVariant[variant.id] ?? []
            let displayTypes = variantRows.map { uploadableDisplayType(for: $0, platform: platform) }
            let unuploadableCount = displayTypes.filter { $0 == nil }.count
            if unuploadableCount == variantRows.count {
                issues.append(UploadIssue(severity: .error, scope: variant.name, message: String(localized: "None of these rows has an App Store screenshot size for \(platform.displayName).")))
            } else if unuploadableCount > 0 {
                issues.append(UploadIssue(severity: .warning, scope: variant.name, message: String(localized: "Some of these rows have no \(platform.displayName) screenshot size and will be skipped.")))
            }
            // The sync engine would reject this too, but only after the experiment exists in App Store Connect.
            let counts = Dictionary(displayTypes.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
            for displayType in ASCDisplayType.allCases where counts[displayType, default: 0] > 1 {
                issues.append(UploadIssue(severity: .error, scope: variant.name, message: String(localized: "More than one row is \(displayType.label). A treatment takes one row per screenshot size — move one to another variant or exclude it from App Store Connect.")))
            }
        }
        return issues
    }

    /// One upload target per uploadable variant row, parented to its treatment's localizations.
    static func targets(
        rowsByVariant: [UUID: [ScreenshotRow]],
        platform: ASCPlatform,
        experimentName: String,
        treatments: [ASCTreatmentTarget]
    ) -> [ASCUploadTarget] {
        treatments.flatMap { entry -> [ASCUploadTarget] in
            guard !entry.localizations.isEmpty else { return [] }
            return (rowsByVariant[entry.variantId] ?? []).compactMap { row in
                guard let displayType = uploadableDisplayType(for: row, platform: platform) else { return nil }
                return ASCUploadTarget(
                    versionId: entry.treatment.id,
                    versionLabel: "\(experimentName) · \(entry.treatment.name)",
                    parentKind: .treatmentLocalization,
                    rowId: row.id,
                    rowLabel: row.label,
                    rowSize: row.templateSize,
                    displayType: displayType,
                    localizations: entry.localizations,
                    templateCount: row.templates.count
                )
            }
        }
    }
}
