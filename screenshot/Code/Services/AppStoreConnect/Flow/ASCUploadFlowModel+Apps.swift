import Foundation

extension ASCUploadFlowModel {
    // MARK: - Loading apps and choosing a version

    // MARK: - Step transitions

    func loadAppsIfNeeded() async {
        guard credentials.isConfigured, appsWithVersions.isEmpty else { return }
        seedDemoContextIfNeeded()
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            appsWithVersions = try await api.listAppsWithVersions()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if selectedApp == nil,
           let savedId = document?.savedASCAppId,
           let match = apps.first(where: { $0.id == savedId }) {
            selectedApp = match
        }
        if selectedApp == nil,
           let projectName = document?.activeProjectName, !projectName.isEmpty {
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
            localeCodes: localeState.locales.map(\.code),
            rowSizes: rows.map(\.templateSize)
        )
    }

    func moveToVersion() async {
        guard let app = selectedApp else { return }
        if !credentials.isDemoMode {
            document?.rememberASCAppId(app.id)
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let fetched = try await api.listAppStoreVersions(appId: app.id)
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
            updateDestinationPlans([])
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
            rows.contains { row in
                guard !row.excludeFromAppStoreConnect,
                      let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
                else { return false }
                return detected.accepts(platform: version.attributes.ascPlatform)
            }
        }
        let defaultVersions = compatible.isEmpty ? Array(editable.prefix(1)) : compatible
        return Set(defaultVersions.map(\.id))
    }

}
