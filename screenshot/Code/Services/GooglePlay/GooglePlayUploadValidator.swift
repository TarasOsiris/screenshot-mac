import Foundation

nonisolated enum GooglePlayUploadValidator {
    /// Pre-flight checks that need no rendering or network. In demo mode the package name is
    /// irrelevant (no traffic) and per-row issues are softened to warnings so the flow stays walkable.
    static func validate(
        packageName: String,
        plans: [GPRowPlan],
        isDemoMode: Bool
    ) -> [UploadIssue] {
        var issues: [UploadIssue] = []

        if !isDemoMode {
            let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                issues.append(UploadIssue(
                    severity: .error,
                    message: "Enter the app's package name (application ID).",
                    hint: "For example: com.example.myapp"
                ))
            } else if !isValidPackageName(trimmed) {
                issues.append(UploadIssue(
                    severity: .error,
                    message: "\"\(trimmed)\" doesn't look like a valid package name.",
                    hint: "Use the reverse-DNS application ID, e.g. com.example.myapp"
                ))
            }
        }

        let enabledPlans = plans.filter { $0.isEnabled }
        if let blocking = StoreUploadChecks.emptyPlansIssue(planCount: plans.count, enabledCount: enabledPlans.count) {
            issues.append(blocking)
            return issues
        }

        var perRow: [UploadIssue] = []
        var claims: [UploadTargetClaim] = []

        for plan in enabledPlans {
            let rowName = StoreUploadChecks.rowName(plan.rowLabel)
            let sizeLabel = StoreUploadChecks.sizeLabel(plan.rowSize)

            if !GPImageType.accepts(width: plan.rowSize.width, height: plan.rowSize.height) {
                perRow.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Row size \(sizeLabel) is outside Google Play's limits.",
                    hint: "Screenshots must be 320–3840 px per edge with an aspect ratio no greater than 2:1."
                ))
            }

            if plan.templateCount < GPUploadLimits.minScreenshotsPerType {
                perRow.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Google Play requires at least \(GPUploadLimits.minScreenshotsPerType) screenshots per type; this row has \(plan.templateCount).",
                    hint: "Add more screenshot columns to this row."
                ))
            }
            if plan.templateCount > GPUploadLimits.maxScreenshotsPerType {
                perRow.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Google Play allows at most \(GPUploadLimits.maxScreenshotsPerType) screenshots per type; this row has \(plan.templateCount).",
                    hint: "Remove columns to bring the count to \(GPUploadLimits.maxScreenshotsPerType) or fewer."
                ))
            }

            let enabledLocales = plan.localeTargets.filter { $0.isEnabled }
            if enabledLocales.isEmpty {
                perRow.append(UploadIssue(
                    severity: .error,
                    scope: rowName,
                    message: "Enable at least one language to upload to."
                ))
            }

            for locale in enabledLocales {
                claims.append(UploadTargetClaim(
                    rowName: rowName,
                    key: "\(locale.playLanguageCode)|\(plan.selectedAssetType.apiValue)"
                ))
            }
        }

        perRow.append(contentsOf: StoreUploadChecks.collisionIssues(claims) { rowName, partner in
            UploadIssue(
                severity: .error,
                scope: rowName,
                message: "This row uploads to the same Play listing slot as \(partner).",
                hint: "Disable one of these rows or pick a different image type."
            )
        })

        issues.append(contentsOf: isDemoMode ? perRow.map { $0.with(severity: .warning) } : perRow)
        return issues
    }

    /// Reverse-DNS application id: ≥2 segments, each starting with a letter, letters/digits/underscore.
    static func isValidPackageName(_ name: String) -> Bool {
        let segments = name.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy(isValidSegment)
    }

    /// `^[a-zA-Z][a-zA-Z0-9_]*$`, spelled out rather than compiled: `validate` runs on every
    /// SwiftUI render, and this avoids both the regex and a force-try on a literal pattern.
    private static func isValidSegment(_ segment: Substring) -> Bool {
        guard let first = segment.first, first.isASCII, first.isLetter else { return false }
        return segment.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}
