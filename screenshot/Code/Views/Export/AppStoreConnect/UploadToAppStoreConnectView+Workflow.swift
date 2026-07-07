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
            let uploadable = appsWithVersions.filter(\.hasScreenshotUploadableVersion).map(\.app)
            let pool = uploadable.isEmpty ? apps : uploadable
            if let match = Self.closestAppByName(projectName: projectName, in: pool) {
                selectedApp = match
            }
        }
    }

    static let nameMatchThreshold: Double = 0.6
    static let nameMatchContainmentBonus: Double = 0.2

    static func closestAppByName(projectName: String, in apps: [ASCApp]) -> ASCApp? {
        let targetString = normalizedName(projectName)
        let target = Array(targetString)
        guard !target.isEmpty else { return nil }

        var bestApp: ASCApp?
        var bestScore = -Double.infinity
        for app in apps {
            let candidateString = normalizedName(app.attributes.name)
            let candidate = Array(candidateString)
            guard !candidate.isEmpty else { continue }
            let distance = levenshtein(candidate, target)
            let similarity = 1.0 - Double(distance) / Double(max(candidate.count, target.count))
            let isContained = candidateString.contains(targetString) || targetString.contains(candidateString)
            let score = similarity + (isContained ? nameMatchContainmentBonus : 0)
            if score > bestScore {
                bestScore = score
                bestApp = app
            }
        }
        return bestScore >= nameMatchThreshold ? bestApp : nil
    }

    static func normalizedName(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
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
                if lhs.isScreenshotUploadable != rhs.isScreenshotUploadable { return lhs.isScreenshotUploadable }
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
        let editable = versions.filter(\.isScreenshotUploadable)
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

    /// Patch a version localization, gracefully dropping "What's New" when App Store Connect
    /// rejects it. The first version of a brand-new app has no release notes, so a `whatsNew`
    /// edit returns 409 ("Attribute 'whatsNew' cannot be edited at this time"); retry without it
    /// so the remaining metadata still saves.
    static func patchVersionLocalization(
        _ api: AppStoreConnectAPIService,
        id: String,
        changes: [String: AnyEncodable]
    ) async throws {
        do {
            try await api.updateVersionLocalization(id: id, attributes: changes)
        } catch let error as AppStoreConnectAPIError {
            guard case let .httpError(status, message) = error,
                  status == 409,
                  message.contains("whatsNew"),
                  changes["whatsNew"] != nil
            else { throw error }
            var retry = changes
            retry.removeValue(forKey: "whatsNew")
            guard !retry.isEmpty else { return }
            try await api.updateVersionLocalization(id: id, attributes: retry)
        }
    }

    func saveMetadataAndContinue() async {
        guard !selectedVersions.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let changedCopyrights = copyrightByVersion.filter { $0.value != (originalCopyrightByVersion[$0.key] ?? "") }
        let versionSnapshot = versionDrafts
        let appInfoSnapshot = appInfoDrafts
        let api = AppStoreConnectAPIService.shared

        do {
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
                        try await Self.patchVersionLocalization(api, id: draft.id, changes: changes)
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
            for (versionId, copyrightValue) in changedCopyrights {
                originalCopyrightByVersion[versionId] = copyrightValue
            }
            for i in versionDrafts.indices where versionDrafts[i].isChanged {
                versionDrafts[i].markSaved()
            }
            for i in appInfoDrafts.indices where appInfoDrafts[i].isChanged {
                appInfoDrafts[i].markSaved()
            }
            destinationPlans = buildDestinationPlans(preserving: destinationPlans)
            advance(to: .configuringPlan)
        } catch {
            errorMessage = String(localized: "Failed to save metadata: \(error.localizedDescription)")
        }
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

    func buildDestinationPlans(preserving existingPlans: [DestinationPlan] = []) -> [DestinationPlan] {
        selectedVersions.map { version in
            let versionLocalizations = localizationsByVersionId[version.id] ?? []
            let existingDestination = existingPlans.first(where: { $0.id == version.id })
            return DestinationPlan(
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
        preserving existingPlans: [RowPlan] = []
    ) -> [RowPlan] {
        let platform = version.attributes.ascPlatform
        let demoFallbackDisplayType = credentials.isDemoMode
            ? ASCDisplayType.userSelectableCases(forPlatform: platform).first
            : nil
        let assignment = ASCLocaleMatcher.assign(appCodes: state.localeState.locales.map(\.code), to: localizations)
        return state.rows.filter { !$0.excludeFromAppStoreConnect }.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> LocaleTarget in
                let matches = assignment[locale.code] ?? []
                let candidateIds = Set(matches.map(\.id))
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                // Preserve the prior selection, but if none of it survives the refreshed
                // candidate set, fall back to selecting all (same as a fresh target) rather
                // than leaving an enabled locale with nothing selected, which hard-blocks upload.
                let preserved = existingTarget.map { $0.selectedASCLocalizationIds.intersection(candidateIds) }
                let selectedIds = (preserved?.isEmpty == false) ? preserved! : candidateIds
                return LocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationIds: selectedIds,
                    candidates: matches,
                    isEnabled: matches.isEmpty ? false : (existingTarget?.isEnabled ?? true)
                )
            }
            let compatiblePreserved = existingPlan?.selectedDisplayType.flatMap { $0.accepts(platform: platform) ? $0 : nil }
            let detectedCompatible = (detected?.accepts(platform: platform) ?? false) ? detected : nil
            let detectedIncompatible = detected != nil && detectedCompatible == nil
            return RowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: row.templateSize,
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? (row.inferredStorePlatform != .android && !detectedIncompatible),
                detectedDisplayType: detected,
                selectedDisplayType: compatiblePreserved ?? detectedCompatible ?? demoFallbackDisplayType,
                localeTargets: targets,
                inferredStorePlatform: row.inferredStorePlatform
            )
        }
    }

    func startUpload() async {
        errorMessage = nil
        errorDetailsText = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = String(localized: "Fix the preflight errors before uploading.")
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = String(localized: "No rows × locales are selected.")
            step = .configuringPlan
            return
        }

        uploadProgress = nil   // clear any stale progress from a previous attempt
        advance(to: .uploading)
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                try await AppStoreConnectUploadService.shared.upload(
                    targets: targets,
                    appState: state,
                    progress: { p in self.uploadProgress = p }
                )
                // `upload` is cancellation-aware and throws `CancellationError` if cancelled
                // mid-flight (handled below). Reaching here means it completed, so show the
                // result even if a Cancel tap landed late — otherwise the wizard would be
                // stranded on the uploading screen (Back hidden, only a no-op Cancel button).
                let summary = UploadSummary(
                    appId: selectedApp?.id,
                    appName: selectedApp?.attributes.name ?? "",
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.localizations.count },
                    localizationCount: Set(targets.flatMap { target in
                        target.localizations.map { "\(target.versionId)|\($0.id)" }
                    }).count,
                    versionCount: Set(targets.map(\.versionId)).count
                )
                uploadSummary = summary
                step = .done
                let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
                let locNoun = summary.localizationCount == 1 ? String(localized: "locale") : String(localized: "locales")
                let versionNoun = summary.versionCount == 1 ? String(localized: "version") : String(localized: "versions")
                let body = summary.appName.isEmpty
                    ? String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun)")
                    : String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) and \(summary.versionCount) \(versionNoun) · \(summary.appName)")
                NotificationService.notify(title: String(localized: "Upload complete"), body: body)
            } catch is CancellationError {
                errorMessage = String(localized: "Upload cancelled. Any set that was already being replaced may be empty in App Store Connect — re-run the upload to refill it.")
                retreatToConfiguringPlan()
            } catch {
                let summary = uploadFailureSummary(for: error)
                errorMessage = summary
                errorDetailsText = buildErrorDetails(for: error)
                retreatToConfiguringPlan()
                NotificationService.notify(title: String(localized: "Upload failed"), body: summary)
            }
        }
        uploadTask = task
        await task.value
    }

    func buildUploadTargets() -> [ASCUploadTarget] {
        destinationPlans.flatMap { destination -> [ASCUploadTarget] in
            destination.rowPlans.compactMap { plan -> ASCUploadTarget? in
                guard plan.isEnabled, let displayType = plan.selectedDisplayType else { return nil }
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
