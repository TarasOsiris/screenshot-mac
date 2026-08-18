import Foundation

extension ASCUploadFlowModel {
    // MARK: - Building the upload plan

    /// Left as a computed property rather than memoized: it is O(destinations × rows), and it
    /// depends on `credentials.isDemoMode`, which can flip from a separate Settings window.
    var validationIssues: [UploadIssue] {
        AppStoreConnectUploadValidator.validate(
            destinations: destinationPlans,
            isDemoMode: credentials.isDemoMode
        )
    }

    var canStartUpload: Bool {
        !validationIssues.hasErrors
    }
    func moveToPlan() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await loadSelectedVersionLocalizations()
            updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
            advance(to: .configuringPlan)
        } catch {
            errorMessage = String(localized: "Could not load App Store data: \(error.localizedDescription)")
        }
    }

    func refreshLocalizations() async {
        guard !selectedVersions.isEmpty else { return }
        seedDemoContextIfNeeded()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await loadSelectedVersionLocalizations()
            updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
        } catch {
            errorMessage = String(localized: "Could not refresh locales: \(error.localizedDescription)")
        }
    }

    func loadSelectedVersionLocalizations() async throws {
        for version in selectedVersions {
            let fetched = try await api.listLocalizations(versionId: version.id)
            localizationsByVersionId[version.id] = fetched
        }
    }

    func buildDestinationPlans(preserving existingPlans: [ASCDestinationPlan] = []) -> [ASCDestinationPlan] {
        selectedVersions.map { version in
            let versionLocalizations = localizationsByVersionId[version.id] ?? []
            let existingDestination = existingPlans.first(where: { $0.id == version.id })
            return ASCDestinationPlan(
                id: version.id,
                version: version,
                localizations: versionLocalizations,
                rowPlans: buildRowPlans(
                    for: version,
                    localizations: versionLocalizations,
                    preserving: existingDestination?.rowPlans ?? []
                )
            )
        }
    }

    func buildRowPlans(
        for version: ASCAppStoreVersion,
        localizations: [ASCAppStoreVersionLocalization],
        preserving existingPlans: [ASCRowPlan] = []
    ) -> [ASCRowPlan] {
        let platform = version.attributes.ascPlatform
        let demoFallbackDisplayType = credentials.isDemoMode
            ? ASCDisplayType.userSelectableCases(forPlatform: platform).first
            : nil
        let assignment = ASCLocaleMatcher.assign(appCodes: localeState.locales.map(\.code), to: localizations)
        return rows.filter { !$0.excludeFromAppStoreConnect }.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = localeState.locales.map { locale -> ASCLocaleTarget in
                let matches = assignment[locale.code] ?? []
                let candidateIds = Set(matches.map(\.id))
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                // Preserve the prior selection, but if none of it survives the refreshed
                // candidate set, fall back to selecting all (same as a fresh target) rather
                // than leaving an enabled locale with nothing selected, which hard-blocks upload.
                let preserved = existingTarget.map { $0.selectedASCLocalizationIds.intersection(candidateIds) }
                let selectedIds = (preserved?.isEmpty == false) ? preserved! : candidateIds
                return ASCLocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationIds: selectedIds,
                    candidates: matches,
                    isEnabled: matches.isEmpty ? false : (existingTarget?.isEnabled ?? true)
                )
            }
            let compatiblePreserved = existingPlan?.selectedAssetType.flatMap { $0.accepts(platform: platform) ? $0 : nil }
            let detectedCompatible = (detected?.accepts(platform: platform) ?? false) ? detected : nil
            let detectedIncompatible = detected != nil && detectedCompatible == nil
            return ASCRowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: row.templateSize,
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? (row.inferredStorePlatform != .android && !detectedIncompatible),
                detectedAssetType: detected,
                selectedAssetType: compatiblePreserved ?? detectedCompatible ?? demoFallbackDisplayType,
                localeTargets: targets,
                inferredStorePlatform: row.inferredStorePlatform
            )
        }
    }
}
