import Foundation

extension ASCUploadFlowModel {
    // MARK: - Creating the next App Store version

    /// The platforms the version step can offer to create a version for: the ones the app already
    /// has a version on, so the platform is known to be enabled for this app. Only meaningful when
    /// no version is selectable — creating a second editable version for a platform is not
    /// something App Store Connect allows.
    var platformsAwaitingAVersion: [ASCPlatform] {
        guard !versions.contains(where: { $0.isSelectable(for: mode) }) else { return [] }
        var seen: [ASCPlatform] = []
        for platform in versions.compactMap({ $0.attributes.ascPlatform }) where !seen.contains(platform) {
            seen.append(platform)
        }
        return seen
    }

    /// The version string to prefill for `platform`: a bump of the highest one the app already has
    /// there, since App Store Connect only accepts a value greater than the current release.
    func suggestedVersionString(platform: ASCPlatform) -> String? {
        let existing = versions
            .filter { $0.attributes.ascPlatform == platform }
            .map(\.attributes.versionString)
        guard let highest = ASCVersionNumber.highest(of: existing) else { return nil }
        return ASCVersionNumber.next(after: highest)
    }

    /// Create the next version so the user doesn't have to leave for the website and come back.
    /// On success it joins `versions` in the position a fetch would have put it in, and becomes
    /// the selection — it is by definition the only editable one.
    func createAppStoreVersion(platform: ASCPlatform, versionString: String) async {
        let trimmed = versionString.trimmingCharacters(in: .whitespaces)
        guard let app = selectedApp, !trimmed.isEmpty, creatingVersionPlatform == nil else { return }

        creatingVersionPlatform = platform
        versionCreationError = nil
        defer { creatingVersionPlatform = nil }

        CrashReportingService.breadcrumb(.upload, "asc create app store version", data: ["platform": platform.rawValue])
        do {
            let created = try await api.createAppStoreVersion(
                appId: app.id,
                platform: platform,
                versionString: trimmed
            )
            var updated = versions.filter { $0.id != created.id }
            updated.append(created)
            versions = sortedForSelection(updated)
            selectedVersionIds = defaultSelectedVersionIds(from: versions)
            localizationsByVersionId[created.id] = nil
        } catch {
            versionCreationError = error.localizedDescription
            CrashReportingService.breadcrumb(
                .upload,
                "asc create app store version failed",
                data: ["platform": platform.rawValue],
                level: .warning
            )
        }
    }
}
