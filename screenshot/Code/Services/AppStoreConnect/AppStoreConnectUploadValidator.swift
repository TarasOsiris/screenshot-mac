import Foundation

// Apple's specs allow 1–10 assets per display type; three is a marketing convention, not a rule.
enum ASCUploadLimits {
    static let minScreenshotsPerSet = 1
    static let recommendedScreenshotsPerSet = 3
    static let maxScreenshotsPerSet = 10
}

enum AppStoreConnectUploadValidator {
    /// In demo mode the upload is simulated, so per-row App Store rules (size match, screenshot
    /// count, duplicate target, locale matching) become advisory warnings instead of hard blockers
    /// — the wizard must run end-to-end for any project. Structural issues (no rows / no enabled
    /// rows / version not editable) keep their original severity.
    static func validate(destinations: [ASCDestinationPlan], isDemoMode: Bool) -> [UploadIssue] {
        if destinations.isEmpty {
            return [
                UploadIssue(
                    severity: .error,
                    message: String(localized: "Select at least one editable version.")
                )
            ]
        }

        return destinations.flatMap { destination in
            validate(version: destination.version, plans: destination.rowPlans)
                .map { $0.scoped(to: destination.title) }
                .map { isDemoMode && $0.demoDowngradable ? $0.with(severity: .warning) : $0 }
        }
    }

    /// Runs all pre-flight checks that don't require rendering or network calls.
    static func validate(
        version: ASCAppStoreVersion,
        plans: [ASCRowPlan]
    ) -> [UploadIssue] {
        var issues: [UploadIssue] = []

        if !version.isScreenshotUploadable {
            issues.append(UploadIssue(
                severity: .error,
                message: String(localized: "Version \(version.attributes.versionString) is \(version.attributes.displayState). Screenshots can only be changed when the version is editable."),
                hint: String(localized: "Create a new version in App Store Connect, or wait for this one to return to an editable state.")
            ))
        }

        let enabledPlans = plans.filter { $0.isEnabled }
        if let blocking = StoreUploadChecks.emptyPlansIssue(planCount: plans.count, enabledCount: enabledPlans.count) {
            issues.append(blocking)
            return issues
        }

        var claims: [UploadTargetClaim] = []

        for plan in enabledPlans {
            let rowName = StoreUploadChecks.rowName(plan.rowLabel)
            let sizeLabel = StoreUploadChecks.sizeLabel(plan.rowSize)
            let detectedTypeFix = detectedAssetTypeFix(for: plan, version: version)

            guard let displayType = plan.selectedAssetType else {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "Pick a display type for this row (\(sizeLabel))."),
                    hint: String(localized: "Use the \"Display Type\" picker above."),
                    demoDowngradable: true,
                    fix: detectedTypeFix
                ))
                continue
            }

            if !displayType.accepts(width: plan.rowSize.width, height: plan.rowSize.height) {
                let accepted = displayType.acceptedPortraitSizes
                    .map { "\($0.0)×\($0.1)" }
                    .joined(separator: ", ")
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "Row size \(sizeLabel) isn't accepted by App Store Connect for \(displayType.label)."),
                    hint: accepted.isEmpty
                        ? String(localized: "Pick a different display type.")
                        : String(localized: "Resize the row to one of: \(accepted), or pick a matching display type."),
                    demoDowngradable: true,
                    fix: detectedTypeFix
                ))
            }

            if let platform = version.attributes.ascPlatform,
               !displayType.accepts(platform: platform) {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "\(displayType.label) can't be uploaded to a \(platform.displayName) version."),
                    hint: String(localized: "Pick a display type that matches the app's platform."),
                    demoDowngradable: true,
                    fix: detectedTypeFix
                ))
            }

            if plan.templateCount < ASCUploadLimits.minScreenshotsPerSet {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "This row has no screenshots to upload."),
                    hint: String(localized: "Add at least one screenshot column to this row."),
                    demoDowngradable: true
                ))
            } else if plan.templateCount < ASCUploadLimits.recommendedScreenshotsPerSet {
                issues.append(UploadIssue(
                    severity: .warning,
                    scope: rowName,
                    message: plan.templateCount == 1
                        ? String(localized: "This row uploads 1 screenshot. App Store Connect accepts \(ASCUploadLimits.minScreenshotsPerSet)–\(ASCUploadLimits.maxScreenshotsPerSet), but most apps show at least \(ASCUploadLimits.recommendedScreenshotsPerSet).")
                        : String(localized: "This row uploads \(plan.templateCount) screenshots. App Store Connect accepts \(ASCUploadLimits.minScreenshotsPerSet)–\(ASCUploadLimits.maxScreenshotsPerSet), but most apps show at least \(ASCUploadLimits.recommendedScreenshotsPerSet)."),
                    hint: String(localized: "Add more screenshot columns, or upload as is.")
                ))
            }
            if plan.templateCount > ASCUploadLimits.maxScreenshotsPerSet {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "App Store Connect allows at most \(ASCUploadLimits.maxScreenshotsPerSet) screenshots per display type; this row has \(plan.templateCount)."),
                    hint: String(localized: "Remove columns to bring the count to \(ASCUploadLimits.maxScreenshotsPerSet) or fewer."),
                    demoDowngradable: true
                ))
            }

            let matchable = plan.localeTargets.filter { !$0.candidates.isEmpty }
            let activeLocaleCount = plan.localeTargets.count { $0.isEnabled && !$0.selectedASCLocalizationIds.isEmpty }
            if activeLocaleCount == 0 {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "Pick at least one App Store locale to upload to."),
                    hint: String(localized: "Enable a locale checkbox and choose an App Store locale."),
                    demoDowngradable: true,
                    fix: matchable.isEmpty ? nil : UploadIssueFix(
                        .selectMatchingStoreLocales,
                        destinationId: version.id,
                        rowId: plan.id,
                        appLocaleCodes: matchable.map(\.appLocaleCode)
                    )
                ))
            }

            // selectedCandidates, not the raw id set: it is what actually uploads, and it is ordered.
            for localeTarget in plan.localeTargets where localeTarget.isEnabled {
                for candidate in localeTarget.selectedCandidates {
                    claims.append(UploadTargetClaim(
                        rowId: plan.id,
                        rowName: rowName,
                        targetLabel: localeTarget.appLocaleLabel,
                        key: "\(candidate.id)|\(displayType.appStoreConnectValue)",
                        slotLabel: candidate.attributes.locale
                    ))
                }
            }

            let missingSelection = plan.localeTargets.filter { $0.isEnabled && !$0.candidates.isEmpty && $0.selectedASCLocalizationIds.isEmpty }
            if !missingSelection.isEmpty {
                let names = missingSelection.map(\.appLocaleLabel).formatted(.list(type: .and))
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: missingSelection.count == 1
                        ? String(localized: "Choose the App Store locale for \(names).")
                        : String(localized: "Choose App Store locales for \(names)."),
                    hint: missingSelection.count == 1
                        ? String(localized: "Use the locale picker in this row, or disable this locale.")
                        : String(localized: "Use the locale pickers in this row, or disable these locales."),
                    demoDowngradable: true,
                    fix: UploadIssueFix(
                        .selectMatchingStoreLocales,
                        destinationId: version.id,
                        rowId: plan.id,
                        appLocaleCodes: missingSelection.map(\.appLocaleCode)
                    )
                ))
            }

            let unmatched = plan.localeTargets.filter { $0.isEnabled && $0.candidates.isEmpty }
            if !unmatched.isEmpty {
                let names = unmatched.map(\.appLocaleLabel).formatted(.list(type: .and))
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "No App Store locale matches \(names) on this version."),
                    hint: unmatched.count == 1
                        ? String(localized: "Add the locale in App Store Connect, or disable this locale here.")
                        : String(localized: "Add the locales in App Store Connect, or disable them here."),
                    demoDowngradable: true
                ))
            }
        }

        issues.append(contentsOf: StoreUploadChecks.collisionIssues(
            claims,
            sameRow: { rowName, localeLabels, ascLocale in
                let names = localeLabels.formatted(.list(type: .and))
                return UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: localeLabels.count == 2
                        ? String(localized: "\(names) both upload to the \(ascLocale) App Store localization.")
                        : String(localized: "\(names) all upload to the \(ascLocale) App Store localization."),
                    hint: String(localized: "Pick a different App Store locale for one of them, or turn one off."),
                    demoDowngradable: true
                )
            },
            otherRow: { rowName, partner in
                UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: String(localized: "This row uploads to the same App Store screenshot set as \(partner)."),
                    hint: String(localized: "Disable one of these rows or choose a different display type before uploading."),
                    demoDowngradable: true
                )
            }
        ))

        return issues
    }

    /// Offered only when the detected type is something the row could actually upload as — a
    /// detection that fails the same size/platform checks would swap one error for another.
    private static func detectedAssetTypeFix(
        for plan: ASCRowPlan,
        version: ASCAppStoreVersion
    ) -> UploadIssueFix? {
        guard let detected = plan.detectedAssetType,
              detected != plan.selectedAssetType,
              detected.accepts(width: plan.rowSize.width, height: plan.rowSize.height),
              version.attributes.ascPlatform.map({ detected.accepts(platform: $0) }) ?? true
        else { return nil }
        return UploadIssueFix(.useDetectedAssetType, destinationId: version.id, rowId: plan.id)
    }
}
