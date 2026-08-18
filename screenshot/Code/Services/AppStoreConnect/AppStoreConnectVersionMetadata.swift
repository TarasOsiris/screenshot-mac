import Foundation

/// Write policies for version-localization metadata that aren't the API client's business —
/// they encode what App Store Connect will accept, not how to talk to it.
enum AppStoreConnectVersionMetadata {
    /// Patch a version localization, gracefully dropping "What's New" when App Store Connect
    /// rejects it. The first version of a brand-new app has no release notes, so a `whatsNew`
    /// edit returns 409 ("Attribute 'whatsNew' cannot be edited at this time"); retry without it
    /// so the remaining metadata still saves.
    static func patchLocalization(
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
}
