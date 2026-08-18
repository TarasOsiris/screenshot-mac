import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - Step transitions

    func loadAppsIfNeeded() async {
        guard credentials.isConfigured, appsWithVersions.isEmpty else { return }
        seedDemoContextIfNeeded()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            appsWithVersions = try await AppStoreConnectAPIService.shared.listAppsWithVersions()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if selectedApp == nil,
           let savedId = state.activeProject?.ascAppId,
           let match = apps.first(where: { $0.id == savedId }) {
            selectedApp = match
        }
        if selectedApp == nil,
           let projectName = state.activeProject?.name {
            let selectable = appsWithVersions.filter { $0.hasSelectableVersion(for: mode) }.map(\.app)
            let pool = selectable.isEmpty ? apps : selectable
            if let match = AppStoreConnectAppMatcher.closestApp(projectName: projectName, in: pool) {
                selectedApp = match
            }
        }
    }

    /// Reseeds the demo catalog with the active project's locales and row sizes so the
    /// wizard finds a matching version platform and a matching App Store locale for
    /// every project locale. No-op when not in demo mode.
    func seedDemoContextIfNeeded() {
        guard credentials.isDemoMode else { return }
        AppStoreConnectDemoData.shared.updateContext(
            localeCodes: state.localeState.locales.map(\.code),
            rowSizes: state.rows.map(\.templateSize)
        )
    }

    func moveToVersion() async {
        guard let app = selectedApp else { return }
        if !credentials.isDemoMode, let projectId = state.activeProject?.id {
            state.setASCAppId(app.id, forProject: projectId)
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let fetched = try await AppStoreConnectAPIService.shared.listAppStoreVersions(appId: app.id)
            versions = fetched.sorted { lhs, rhs in
                let lhsSelectable = lhs.isSelectable(for: mode)
                let rhsSelectable = rhs.isSelectable(for: mode)
                if lhsSelectable != rhsSelectable { return lhsSelectable }
                if lhs.attributes.displayPlatform != rhs.attributes.displayPlatform {
                    return (lhs.attributes.displayPlatform ?? "") < (rhs.attributes.displayPlatform ?? "")
                }
                return lhs.attributes.versionString.compare(
                    rhs.attributes.versionString,
                    options: .numeric
                ) == .orderedDescending
            }
            selectedVersionIds = defaultSelectedVersionIds(from: versions)
            localizationsByVersionId = [:]
            destinationPlans = []
            advance(to: .pickingVersion)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func defaultSelectedVersionIds(from versions: [ASCAppStoreVersion]) -> Set<String> {
        let editable = versions.filter { $0.isSelectable(for: mode) }
        // Metadata edits don't involve rows, so every editable version is a valid default.
        guard mode == .screenshots else { return Set(editable.map(\.id)) }
        let compatible = editable.filter { version in
            state.rows.contains { row in
                guard !row.excludeFromAppStoreConnect,
                      let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
                else { return false }
                return detected.accepts(platform: version.attributes.ascPlatform)
            }
        }
        let defaultVersions = compatible.isEmpty ? Array(editable.prefix(1)) : compatible
        return Set(defaultVersions.map(\.id))
    }

    func movePastVersionSelection() async {
        await moveToMetadata()
    }

    func moveToMetadata() async {
        guard let app = selectedApp, !selectedVersions.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            async let appInfosTask = AppStoreConnectAPIService.shared.listAppInfos(appId: app.id)
            try await loadSelectedVersionLocalizations()
            let fetchedAppInfos = try await appInfosTask

            let editableInfo = fetchedAppInfos.first(where: { $0.isEditable }) ?? fetchedAppInfos.first
            let fetchedAppInfoLocalizations: [ASCAppInfoLocalization]
            if let editableInfo {
                fetchedAppInfoLocalizations = try await AppStoreConnectAPIService.shared.listAppInfoLocalizations(appInfoId: editableInfo.id)
            } else {
                fetchedAppInfoLocalizations = []
            }

            if !selectedVersions.contains(where: { $0.id == metadataVersionId }) {
                metadataVersionId = selectedVersions.first?.id
            }
            buildMetadataDrafts(appInfoLocalizations: fetchedAppInfoLocalizations)
            advance(to: .editingMetadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static let defaultWhatsNew = "New features and bug fixes"

    func buildMetadataDrafts(appInfoLocalizations: [ASCAppInfoLocalization]) {
        var allVersionDrafts: [VersionLocaleDraft] = []
        var copyrights: [String: String] = [:]
        for version in selectedVersions {
            let sorted = (localizationsByVersionId[version.id] ?? [])
                .sorted { $0.attributes.locale < $1.attributes.locale }
            let englishWhatsNew = sorted
                .first { $0.attributes.locale.lowercased().hasPrefix("en") }
                .flatMap { $0.attributes.whatsNew?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? Self.defaultWhatsNew
            allVersionDrafts += sorted.map { loc in
                let existing = loc.attributes.whatsNew?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let whatsNew = existing.isEmpty ? englishWhatsNew : existing
                return VersionLocaleDraft(
                    id: loc.id,
                    versionId: version.id,
                    locale: loc.attributes.locale,
                    description: loc.attributes.description ?? "",
                    keywords: loc.attributes.keywords ?? "",
                    promotionalText: loc.attributes.promotionalText ?? "",
                    whatsNew: whatsNew,
                    marketingUrl: loc.attributes.marketingUrl ?? "",
                    supportUrl: loc.attributes.supportUrl ?? "",
                    original: loc.attributes
                )
            }
            copyrights[version.id] = version.attributes.copyright ?? ""
        }
        versionDrafts = allVersionDrafts
        originalCopyrightByVersion = copyrights
        copyrightByVersion = copyrights
        appInfoDrafts = appInfoLocalizations
            .sorted { $0.attributes.locale < $1.attributes.locale }
            .map { loc in
                AppInfoLocaleDraft(
                    id: loc.id,
                    locale: loc.attributes.locale,
                    name: loc.attributes.name ?? "",
                    subtitle: loc.attributes.subtitle ?? "",
                    privacyPolicyUrl: loc.attributes.privacyPolicyUrl ?? "",
                    original: loc.attributes
                )
            }
        let codes = metadataLocaleCodes
        let currentStillValid = selectedMetadataLocale.map(codes.contains) ?? false
        if !currentStillValid {
            selectedMetadataLocale = codes.first
        }
    }

    /// Metadata locales for the active version's tab: that version's localizations ∪ the
    /// shared app-info locales.
    var metadataLocaleCodes: [String] {
        let versionLocales = versionDrafts.filter { $0.versionId == metadataVersionId }.map(\.locale)
        let sorted = Set(versionLocales).union(appInfoDrafts.map(\.locale)).sorted()
        guard let base = baseLocaleCode(among: sorted) else { return sorted }
        return [base] + sorted.filter { $0 != base }
    }

    /// The App Store Connect locale code matching the project's base locale, if present among
    /// the metadata locales: exact match first, then the conventional same-region variant
    /// ("en" → "en-US", "fr" → "fr-FR"), then the first region variant ("zh" → "zh-Hans").
    /// `codes` must be sorted so the final fallback is deterministic.
    func baseLocaleCode(among codes: [String]) -> String? {
        let base = state.localeState.baseLocaleCode.lowercased()
        let conventional = "\(base)-\(base)"
        return codes.first { $0.lowercased() == base }
            ?? codes.first { $0.lowercased() == conventional }
            ?? codes.first { $0.lowercased().hasPrefix(base + "-") }
    }

    func saveMetadataAndContinue() async {
        guard !selectedVersions.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        do {
            let summary = try await saveMetadataChanges()
            switch mode {
            case .screenshots:
                destinationPlans = buildDestinationPlans(preserving: destinationPlans)
                advance(to: .configuringPlan)
            case .metadata:
                metadataSummary = summary
                advance(to: .done)
            }
        } catch {
            errorMessage = String(localized: "Failed to save metadata: \(error.localizedDescription)")
        }
    }

    /// Patches every changed draft (copyright, version localizations, app-info localizations) in
    /// parallel, then re-baselines the drafts so the change dots clear. Returns what was written.
    func saveMetadataChanges() async throws -> MetadataSaveSummary {
        let changedCopyrights = copyrightByVersion.filter { $0.value != (originalCopyrightByVersion[$0.key] ?? "") }
        let versionSnapshot = versionDrafts
        let appInfoSnapshot = appInfoDrafts
        let api = AppStoreConnectAPIService.shared

        try await withThrowingTaskGroup(of: Void.self) { group in
            for (versionId, copyrightValue) in changedCopyrights {
                group.addTask {
                    try await api.updateAppStoreVersion(
                        id: versionId,
                        attributes: ["copyright": AnyEncodable(copyrightValue)]
                    )
                }
            }
            for draft in versionSnapshot {
                let changes = draft.changedAttributes()
                guard !changes.isEmpty else { continue }
                group.addTask {
                    try await AppStoreConnectVersionMetadata.patchLocalization(api, id: draft.id, changes: changes)
                }
            }
            for draft in appInfoSnapshot {
                let changes = draft.changedAttributes()
                guard !changes.isEmpty else { continue }
                group.addTask {
                    try await api.updateAppInfoLocalization(id: draft.id, attributes: changes)
                }
            }
            try await group.waitForAll()
        }

        let changedVersionDrafts = versionSnapshot.filter(\.isChanged)
        let changedAppInfoDrafts = appInfoSnapshot.filter(\.isChanged)

        for (versionId, copyrightValue) in changedCopyrights {
            originalCopyrightByVersion[versionId] = copyrightValue
        }
        for i in versionDrafts.indices where versionDrafts[i].isChanged {
            versionDrafts[i].markSaved()
        }
        for i in appInfoDrafts.indices where appInfoDrafts[i].isChanged {
            appInfoDrafts[i].markSaved()
        }

        let locales = Set(changedVersionDrafts.map(\.locale)).union(changedAppInfoDrafts.map(\.locale))
        let versionIds = Set(changedVersionDrafts.map(\.versionId)).union(changedCopyrights.keys)
        let fieldCount = changedVersionDrafts.reduce(0) { $0 + $1.changedAttributes().count }
            + changedAppInfoDrafts.reduce(0) { $0 + $1.changedAttributes().count }
            + changedCopyrights.count
        return MetadataSaveSummary(
            appId: selectedApp?.id,
            appName: selectedApp?.attributes.name ?? "",
            versionCount: versionIds.count,
            localeCount: locales.count,
            fieldCount: fieldCount
        )
    }

    func moveToPlan() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await loadSelectedVersionLocalizations()
            destinationPlans = buildDestinationPlans(preserving: destinationPlans)
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
            destinationPlans = buildDestinationPlans(preserving: destinationPlans)
        } catch {
            errorMessage = String(localized: "Could not refresh locales: \(error.localizedDescription)")
        }
    }

    func loadSelectedVersionLocalizations() async throws {
        for version in selectedVersions {
            let fetched = try await AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
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
        let assignment = ASCLocaleMatcher.assign(appCodes: state.localeState.locales.map(\.code), to: localizations)
        return state.rows.filter { !$0.excludeFromAppStoreConnect }.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> ASCLocaleTarget in
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

    func startScreenshotReviewBuild() {
        uploadTask = Task { await buildScreenshotReview() }
    }

    func startDirectScreenshotSync() {
        uploadTask = Task { await buildAndApplyDirectScreenshotSync() }
    }

    func startReviewedScreenshotSync() {
        uploadTask = Task { await applyPreparedScreenshotSync(returnOnFailure: .reviewingChanges) }
    }

    func startScreenshotReviewRefresh() {
        uploadTask = Task { await refreshScreenshotReview() }
    }

    func buildScreenshotReview() async {
        errorMessage = nil
        errorDetailsText = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before reviewing changes.")
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            return
        }
        guard let appId = selectedApp?.id else { return }

        isBusy = true
        defer { isBusy = false; uploadTask = nil }
        advance(to: .reviewingChanges)
        await screenshotSync.build(appId: appId, targets: targets, rows: state.rows, source: state, document: state.documentStamp)
        if screenshotSync.plan == nil {
            errorMessage = screenshotSync.errorMessage
        }
    }

    func refreshScreenshotReview() async {
        guard let appId = selectedApp?.id else { return }
        isBusy = true
        defer { isBusy = false; uploadTask = nil }
        await screenshotSync.build(appId: appId, targets: buildUploadTargets(), rows: state.rows, source: state, document: state.documentStamp)
        errorMessage = screenshotSync.errorMessage
    }

    func buildAndApplyDirectScreenshotSync() async {
        errorMessage = nil
        errorDetailsText = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            uploadTask = nil
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            uploadTask = nil
            return
        }
        guard let appId = selectedApp?.id else {
            uploadTask = nil
            return
        }

        uploadProgress = UploadProgress(totalSteps: 1, completedSteps: 0, currentLabel: "Preparing safe screenshot sync…")
        advance(to: .uploading)
        isBusy = true
        await screenshotSync.build(appId: appId, targets: targets, rows: state.rows, source: state, document: state.documentStamp)
        isBusy = false

        guard let plan = screenshotSync.plan else {
            if !screenshotSync.wasCancelled {
                errorMessage = screenshotSync.errorMessage ?? String(localized: "Could not prepare the screenshot sync.")
                errorDetailsText = errorMessage
            }
            uploadTask = nil
            retreatAfterScreenshotSync(to: .configuringPlan)
            return
        }

        let blockedSets = plan.changedSets.filter { !$0.canApply }
        guard blockedSets.isEmpty else {
            errorMessage = String(localized: "Some screenshot sets require review before they can be synced.")
            errorDetailsText = blockedSets.flatMap(\.issues).joined(separator: "\n")
            uploadTask = nil
            retreatAfterScreenshotSync(to: .configuringPlan)
            return
        }

        let selectedSets = screenshotSync.selectedSets
        if selectedSets.isEmpty {
            finishScreenshotSync(using: plan.sets)
            screenshotSync.discard()
            uploadTask = nil
            return
        }
        await applyPreparedScreenshotSync(
            returnOnFailure: .configuringPlan,
            advanceToUploading: false
        )
    }

    func applyPreparedScreenshotSync(
        returnOnFailure: Step,
        advanceToUploading: Bool = true
    ) async {
        errorMessage = nil
        errorDetailsText = nil
        let selectedSets = screenshotSync.selectedSets
        guard !selectedSets.isEmpty else {
            errorMessage = ASCScreenshotSyncError.noSetsSelected.localizedDescription
            uploadTask = nil
            return
        }

        uploadProgress = nil
        if advanceToUploading {
            advance(to: .uploading)
        }
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        await screenshotSync.apply(document: state.documentStamp, progress: { p in self.uploadProgress = p })
        if screenshotSync.result?.succeeded == true {
            finishScreenshotSync(using: selectedSets)
        } else {
            let message = screenshotSync.errorMessage
                ?? screenshotSync.result?.sets.compactMap(\.error).first
                ?? String(localized: "Screenshot sync did not complete.")
            errorMessage = message
            errorDetailsText = message
            retreatAfterScreenshotSync(to: returnOnFailure)
            NotificationService.notify(title: String(localized: "Screenshot sync stopped"), body: message)
        }
    }

    func finishScreenshotSync(using sets: [ASCScreenshotSetDiff]) {
        let summary = UploadSummary(
            appId: selectedApp?.id,
            appName: selectedApp?.attributes.name ?? "",
            totalScreenshots: sets.reduce(0) { $0 + $1.proposedAssets.count },
            localizationCount: Set(sets.map { "\($0.versionId)|\($0.localizationId)" }).count,
            versionCount: Set(sets.map(\.versionId)).count
        )
        uploadSummary = summary
        step = .done
        let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let locNoun = summary.localizationCount == 1 ? String(localized: "locale") : String(localized: "locales")
        let versionNoun = summary.versionCount == 1 ? String(localized: "version") : String(localized: "versions")
        let body = summary.appName.isEmpty
            ? String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun)")
            : String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun) · \(summary.appName)")
        NotificationService.notify(title: String(localized: "Screenshot sync complete"), body: body)
    }

    func buildUploadTargets() -> [ASCUploadTarget] {
        destinationPlans.flatMap { destination -> [ASCUploadTarget] in
            destination.rowPlans.compactMap { plan -> ASCUploadTarget? in
                guard plan.isEnabled, let displayType = plan.selectedAssetType else { return nil }
                guard let row = state.rows.first(where: { $0.id == plan.id }),
                      !row.excludeFromAppStoreConnect else { return nil }
                let localizations = plan.localeTargets.flatMap { target -> [ASCUploadLocalization] in
                    guard target.isEnabled else { return [] }
                    return target.selectedCandidates
                        .map { ASCUploadLocalization(id: $0.id, label: $0.attributes.locale, localeCode: target.appLocaleCode) }
                }
                guard !localizations.isEmpty else { return nil }
                return ASCUploadTarget(
                    versionId: destination.id,
                    versionLabel: destination.title,
                    rowId: plan.id,
                    rowLabel: plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel,
                    rowSize: plan.rowSize,
                    displayType: displayType,
                    localizations: localizations,
                    templateCount: plan.templateCount
                )
            }
        }
    }

    func uploadFailureSummary(for error: Error) -> String {
        if let uploadError = error as? AppStoreConnectUploadError {
            return uploadError.summaryDescription
        }
        return String(localized: "Upload failed: \(error.localizedDescription)")
    }

    func buildErrorDetails(for error: Error) -> String {
        var details: [String] = [error.localizedDescription]
        if let app = selectedApp {
            details.append("App: \(app.attributes.name) (\(app.attributes.bundleId))")
        }
        if !selectedVersions.isEmpty {
            let versionDetails = selectedVersions.map { version in
                let platform = version.attributes.displayPlatform.map { "\($0) " } ?? ""
                return "\(platform)\(version.attributes.versionString) · \(version.attributes.displayState)"
            }.joined(separator: "\n")
            details.append("Versions:\n\(versionDetails)")
        }
        if let uploadError = error as? AppStoreConnectUploadError {
            details.append("Technical details:\n\(uploadError.technicalDescription)")
        }
        return details.joined(separator: "\n\n")
    }
}
