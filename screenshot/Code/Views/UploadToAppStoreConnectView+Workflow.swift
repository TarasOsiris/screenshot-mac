#if os(macOS)
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
            let uploadable = appsWithVersions.filter(\.hasEditableVersion).map(\.app)
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
                if lhs.isEditable != rhs.isEditable { return lhs.isEditable }
                return lhs.attributes.versionString.compare(
                    rhs.attributes.versionString,
                    options: .numeric
                ) == .orderedDescending
            }
            selectedVersion = versions.first(where: { $0.isEditable }) ?? versions.first
            step = .pickingVersion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func moveToMetadata() async {
        guard let version = selectedVersion, let app = selectedApp else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            async let localizationsTask = AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            async let appInfosTask = AppStoreConnectAPIService.shared.listAppInfos(appId: app.id)
            let (fetchedLocalizations, fetchedAppInfos) = try await (localizationsTask, appInfosTask)
            localizations = fetchedLocalizations

            let editableInfo = fetchedAppInfos.first(where: { $0.isEditable }) ?? fetchedAppInfos.first
            let fetchedAppInfoLocalizations: [ASCAppInfoLocalization]
            if let editableInfo {
                fetchedAppInfoLocalizations = try await AppStoreConnectAPIService.shared.listAppInfoLocalizations(appInfoId: editableInfo.id)
            } else {
                fetchedAppInfoLocalizations = []
            }

            buildMetadataDrafts(appInfoLocalizations: fetchedAppInfoLocalizations)
            step = .editingMetadata
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static let defaultWhatsNew = "New features and bug fixes"

    func buildMetadataDrafts(appInfoLocalizations: [ASCAppInfoLocalization]) {
        let sortedLocalizations = localizations.sorted { $0.attributes.locale < $1.attributes.locale }
        let englishWhatsNew = sortedLocalizations
            .first { $0.attributes.locale.lowercased().hasPrefix("en") }
            .flatMap { $0.attributes.whatsNew?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultWhatsNew

        versionDrafts = sortedLocalizations
            .map { loc in
                let existing = loc.attributes.whatsNew?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let whatsNew = existing.isEmpty ? englishWhatsNew : existing
                return VersionLocaleDraft(
                    id: loc.id,
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
        originalCopyright = selectedVersion?.attributes.copyright ?? ""
        copyrightDraft = originalCopyright
        let codes = metadataLocaleCodes
        let currentStillValid = selectedMetadataLocale.map(codes.contains) ?? false
        if !currentStillValid {
            selectedMetadataLocale = codes.first
        }
    }

    var metadataLocaleCodes: [String] {
        let codes = Set(versionDrafts.map(\.locale)).union(appInfoDrafts.map(\.locale))
        return codes.sorted()
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
        guard let version = selectedVersion else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let copyrightChanged = copyrightDraft != originalCopyright
        let copyrightValue = copyrightDraft
        let versionSnapshot = versionDrafts
        let appInfoSnapshot = appInfoDrafts
        let api = AppStoreConnectAPIService.shared

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                if copyrightChanged {
                    group.addTask {
                        try await api.updateAppStoreVersion(
                            id: version.id,
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
            if copyrightChanged { originalCopyright = copyrightValue }
            for i in versionDrafts.indices where versionDrafts[i].isChanged {
                versionDrafts[i].markSaved()
            }
            for i in appInfoDrafts.indices where appInfoDrafts[i].isChanged {
                appInfoDrafts[i].markSaved()
            }
            rowPlans = buildRowPlans(preserving: rowPlans)
            step = .configuringPlan
        } catch {
            errorMessage = String(localized: "Failed to save metadata: \(error.localizedDescription)")
        }
    }

    func refreshLocalizations() async {
        guard let version = selectedVersion else { return }
        seedDemoContextIfNeeded()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            localizations = try await AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            rowPlans = buildRowPlans(preserving: rowPlans)
        } catch {
            errorMessage = String(localized: "Could not refresh locales: \(error.localizedDescription)")
        }
    }

    func buildRowPlans(preserving existingPlans: [RowPlan] = []) -> [RowPlan] {
        let platform = selectedVersion?.attributes.ascPlatform
        let demoFallbackDisplayType = credentials.isDemoMode
            ? ASCDisplayType.userSelectableCases(forPlatform: platform).first
            : nil
        return state.rows.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> LocaleTarget in
                let matches = ASCLocaleMatcher.matches(appCode: locale.code, in: localizations)
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                let preservedSelection = existingTarget?.selectedASCLocalizationId
                let selectedId: String?
                if let preservedSelection, matches.contains(where: { $0.id == preservedSelection }) {
                    selectedId = preservedSelection
                } else {
                    selectedId = matches.first?.id
                }
                return LocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationId: selectedId,
                    candidates: matches,
                    isEnabled: matches.isEmpty ? false : (existingTarget?.isEnabled ?? true)
                )
            }
            let compatiblePreserved = existingPlan?.selectedDisplayType.flatMap { $0.accepts(platform: platform) ? $0 : nil }
            let detectedCompatible = (detected?.accepts(platform: platform) ?? false) ? detected : nil
            return RowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: row.templateSize,
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? true,
                detectedDisplayType: detected,
                selectedDisplayType: compatiblePreserved ?? detectedCompatible ?? demoFallbackDisplayType,
                localeTargets: targets
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

        step = .uploading
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                try await AppStoreConnectUploadService.shared.upload(
                    targets: targets,
                    appState: state,
                    progress: { p in self.uploadProgress = p }
                )
                if Task.isCancelled { return }
                let summary = UploadSummary(
                    appId: selectedApp?.id,
                    appName: selectedApp?.attributes.name ?? "",
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.localizations.count },
                    localizationCount: Set(targets.flatMap { $0.localizations.map(\.id) }).count
                )
                uploadSummary = summary
                step = .done
                let shotNoun = summary.totalScreenshots == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
                let locNoun = summary.localizationCount == 1 ? String(localized: "locale") : String(localized: "locales")
                let body = summary.appName.isEmpty
                    ? String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun)")
                    : String(localized: "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) · \(summary.appName)")
                NotificationService.notify(title: String(localized: "Upload complete"), body: body)
            } catch is CancellationError {
                errorMessage = String(localized: "Upload cancelled. Any set that was already being replaced may be empty in App Store Connect — re-run the upload to refill it.")
                step = .configuringPlan
            } catch {
                let summary = uploadFailureSummary(for: error)
                errorMessage = summary
                errorDetailsText = buildErrorDetails(for: error)
                step = .configuringPlan
                NotificationService.notify(title: String(localized: "Upload failed"), body: summary)
            }
        }
        uploadTask = task
        await task.value
    }

    func buildUploadTargets() -> [ASCUploadTarget] {
        rowPlans.compactMap { plan -> ASCUploadTarget? in
            guard plan.isEnabled, let displayType = plan.selectedDisplayType else { return nil }
            let localizations = plan.localeTargets.compactMap { target -> ASCUploadLocalization? in
                guard target.isEnabled, let id = target.selectedASCLocalizationId else { return nil }
                return ASCUploadLocalization(id: id, label: target.appLocaleLabel, localeCode: target.appLocaleCode)
            }
            guard !localizations.isEmpty else { return nil }
            return ASCUploadTarget(
                rowId: plan.id,
                rowLabel: plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel,
                rowSize: plan.rowSize,
                displayType: displayType,
                localizations: localizations,
                templateCount: plan.templateCount
            )
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
        if let version = selectedVersion {
            let platform = version.attributes.displayPlatform.map { " \($0)" } ?? ""
            details.append("Version: \(version.attributes.versionString)\(platform) · \(version.attributes.displayState)")
        }
        if let uploadError = error as? AppStoreConnectUploadError {
            details.append("Technical details:\n\(uploadError.technicalDescription)")
        }
        return details.joined(separator: "\n\n")
    }
}

#endif
