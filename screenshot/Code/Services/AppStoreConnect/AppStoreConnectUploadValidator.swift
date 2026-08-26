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
                    message: "Select at least one editable version."
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
                message: "Version \(version.attributes.versionString) is \(version.attributes.displayState). Screenshots can only be changed when the version is editable.",
                hint: "Create a new version in App Store Connect, or wait for this one to return to an editable state."
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

            guard let displayType = plan.selectedAssetType else {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Pick a display type for this row (\(sizeLabel)).",
                    hint: "Use the \"Display type\" picker above.",
                    demoDowngradable: true
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
                    message: "Row size \(sizeLabel) isn't accepted by App Store Connect for \(displayType.label).",
                    hint: accepted.isEmpty
                        ? "Pick a different display type."
                        : "Resize the row to one of: \(accepted), or pick a matching display type.",
                    demoDowngradable: true
                ))
            }

            if let platform = version.attributes.ascPlatform,
               !displayType.accepts(platform: platform) {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "\(displayType.label) can't be uploaded to a \(platform.displayName) version.",
                    hint: "Pick a display type that matches the app's platform.",
                    demoDowngradable: true
                ))
            }

            if plan.templateCount < ASCUploadLimits.minScreenshotsPerSet {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "This row has no screenshots to upload.",
                    hint: "Add at least one screenshot column to this row.",
                    demoDowngradable: true
                ))
            } else if plan.templateCount < ASCUploadLimits.recommendedScreenshotsPerSet {
                let noun = plan.templateCount == 1 ? "screenshot" : "screenshots"
                issues.append(UploadIssue(
                    severity: .warning,
                    scope: rowName,
                    message: "This row uploads \(plan.templateCount) \(noun). App Store Connect accepts \(ASCUploadLimits.minScreenshotsPerSet)–\(ASCUploadLimits.maxScreenshotsPerSet), but most apps show at least \(ASCUploadLimits.recommendedScreenshotsPerSet).",
                    hint: "Add more screenshot columns, or upload as is."
                ))
            }
            if plan.templateCount > ASCUploadLimits.maxScreenshotsPerSet {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "App Store Connect allows at most \(ASCUploadLimits.maxScreenshotsPerSet) screenshots per display type; this row has \(plan.templateCount).",
                    hint: "Remove columns to bring the count to \(ASCUploadLimits.maxScreenshotsPerSet) or fewer.",
                    demoDowngradable: true
                ))
            }

            let activeLocaleCount = plan.localeTargets.count { $0.isEnabled && !$0.selectedASCLocalizationIds.isEmpty }
            if activeLocaleCount == 0 {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Pick at least one App Store locale to upload to.",
                    hint: "Enable a locale checkbox and choose an App Store locale.",
                    demoDowngradable: true
                ))
            }

            for localeTarget in plan.localeTargets where localeTarget.isEnabled {
                for localizationId in localeTarget.selectedASCLocalizationIds {
                    claims.append(UploadTargetClaim(
                        rowName: rowName,
                        key: "\(localizationId)|\(displayType.appStoreConnectValue)"
                    ))
                }
            }

            let missingSelection = plan.localeTargets.filter { $0.isEnabled && !$0.candidates.isEmpty && $0.selectedASCLocalizationIds.isEmpty }
            for target in missingSelection {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Choose the App Store locale for \(target.appLocaleLabel).",
                    hint: "Use the locale picker in this row, or disable this locale.",
                    demoDowngradable: true
                ))
            }

            let unmatched = plan.localeTargets.filter { $0.isEnabled && $0.candidates.isEmpty }
            for target in unmatched {
                issues.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "No App Store locale matches \(target.appLocaleLabel) on this version.",
                    hint: "Add the locale in App Store Connect, or disable this locale here.",
                    demoDowngradable: true
                ))
            }
        }

        issues.append(contentsOf: StoreUploadChecks.collisionIssues(claims) { rowName, partner in
            UploadIssue(
                severity: .error,
                scope: rowName,
                message: "This row uploads to the same App Store screenshot set as \(partner).",
                hint: "Disable one of these rows or choose a different display type before uploading.",
                demoDowngradable: true
            )
        })

        return issues
    }
}
