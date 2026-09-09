import Foundation

/// Write policies for version-localization metadata that aren't the API client's business —
/// they encode what App Store Connect will accept, not how to talk to it.
enum AppStoreConnectVersionMetadata {
    /// Patch a version localization, gracefully dropping "What's New" when App Store Connect
    /// rejects it. The first version of a brand-new app has no release notes, so a `whatsNew`
    /// edit returns 409 ("Attribute 'whatsNew' cannot be edited at this time"); retry without it
    /// so the remaining metadata still saves.
    static func patchLocalization(
        _ api: some ASCUploadAPI,
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

    /// Create a version localization for `locale`. A locale-only create is what the API
    /// documents, but App Store Connect refuses it for an app whose listing already requires
    /// copy per language; retry once, supplying exactly the attributes the rejection named that
    /// `fallbackAttributes` can cover, so the user isn't bounced to the website to paste
    /// placeholder text. Sending the named subset rather than a fixed pair matters because a
    /// shipped app's version is rejected for `whatsNew` alongside `description`, and a retry
    /// that answers only part of the complaint fails again.
    static func createLocalization(
        _ api: some ASCUploadAPI,
        versionId: String,
        locale: String,
        fallbackAttributes: [String: AnyEncodable]
    ) async throws -> ASCAppStoreVersionLocalization {
        do {
            return try await api.createVersionLocalization(versionId: versionId, locale: locale)
        } catch let error as AppStoreConnectAPIError {
            guard case let .httpError(status, message) = error, status == 400 || status == 409 else { throw error }
            let demanded = fallbackAttributes.filter { message.contains($0.key) }
            guard !demanded.isEmpty else { throw error }
            return try await api.createVersionLocalization(
                versionId: versionId,
                locale: locale,
                attributes: demanded
            )
        }
    }
}
