import Foundation

extension ASCUploadFlowModel {
    // MARK: - Editing and saving version / app metadata
    func moveToMetadata() async {
        guard let app = selectedApp, !selectedVersions.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            async let appInfoLocalizationsTask = AppStoreConnectVersionMetadata.editableAppInfoLocalizations(api, appId: app.id)
            try await loadSelectedVersionLocalizations()
            let fetchedAppInfoLocalizations = try await appInfoLocalizationsTask

            if !selectedVersions.contains(where: { $0.id == metadataVersionId }) {
                metadataVersionId = selectedVersions.first?.id
            }
            buildMetadataDrafts(appInfoLocalizations: fetchedAppInfoLocalizations)
            advance(to: .editingMetadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func buildMetadataDrafts(appInfoLocalizations: [ASCAppInfoLocalization]) {
        var allVersionDrafts: [ASCVersionLocaleDraft] = []
        var copyrights: [String: String] = [:]
        for version in selectedVersions {
            let sorted = (localizationsByVersionId[version.id] ?? [])
                .sorted { $0.attributes.locale < $1.attributes.locale }
            // Never prefill empty release notes: the save would PATCH them and silence ASC's "What's New" check.
            allVersionDrafts += sorted.map { loc in
                ASCVersionLocaleDraft(
                    id: loc.id,
                    versionId: version.id,
                    locale: loc.attributes.locale,
                    description: loc.attributes.description ?? "",
                    keywords: loc.attributes.keywords ?? "",
                    promotionalText: loc.attributes.promotionalText ?? "",
                    whatsNew: loc.attributes.whatsNew ?? "",
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
                ASCAppInfoLocaleDraft(
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
        let base = localeState.baseLocaleCode.lowercased()
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
                updateDestinationPlans(buildDestinationPlans(preserving: destinationPlans))
                advance(to: .configuringPlan)
                reloadRemoteScreenshotCounts()
            case .metadata:
                metadataSummary = summary
                advance(to: .done)
            }
        } catch {
            errorMessage = String(localized: "Failed to save metadata: \(error.localizedDescription)")
        }
    }

    /// Patches every changed draft (copyright, version localizations, app-info localizations) a
    /// few at a time, then re-baselines the drafts so the change dots clear. Returns what was
    /// written.
    func saveMetadataChanges() async throws -> ASCMetadataSaveSummary {
        let changedCopyrights = copyrightByVersion.filter { $0.value != (originalCopyrightByVersion[$0.key] ?? "") }
        let versionSnapshot = versionDrafts
        let appInfoSnapshot = appInfoDrafts
        let api = api

        // `@MainActor`, not `@Sendable`: `AnyEncodable` wraps a closure and is not Sendable, so
        // `changes` cannot cross an isolation boundary. Spelling the isolation into the element
        // type is what the inline `addTask` closures used to get by inference.
        var writes: [@MainActor () async throws -> Void] = []
        for (versionId, copyrightValue) in changedCopyrights {
            writes.append {
                try await api.updateAppStoreVersion(
                    id: versionId,
                    attributes: ["copyright": AnyEncodable(copyrightValue)]
                )
            }
        }
        for draft in versionSnapshot {
            let changes = draft.changedAttributes()
            guard !changes.isEmpty else { continue }
            writes.append {
                try await AppStoreConnectVersionMetadata.patchLocalization(api, id: draft.id, changes: changes)
            }
        }
        for draft in appInfoSnapshot {
            let changes = draft.changedAttributes()
            guard !changes.isEmpty else { continue }
            writes.append {
                try await api.updateAppInfoLocalization(id: draft.id, attributes: changes)
            }
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = writes.makeIterator()
            for _ in 0..<AppStoreConnectVersionMetadata.writeConcurrency {
                guard let write = pending.next() else { break }
                group.addTask { try await write() }
            }
            while try await group.next() != nil {
                guard let write = pending.next() else { continue }
                group.addTask { try await write() }
            }
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
        return ASCMetadataSaveSummary(
            appId: selectedApp?.id,
            appName: selectedApp?.attributes.name ?? "",
            versionCount: versionIds.count,
            localeCount: locales.count,
            fieldCount: fieldCount
        )
    }
}
