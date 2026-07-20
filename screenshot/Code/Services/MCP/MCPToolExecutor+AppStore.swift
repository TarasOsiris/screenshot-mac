#if os(macOS)
import Foundation
import MCP

extension MCPToolExecutor {

    struct ASCMetadataResult: Encodable {
        let appId: String
        let versions: [VersionMeta]

        struct VersionMeta: Encodable {
            let versionId: String
            let platform: String?
            let versionString: String
            let appStoreState: String?
            let editable: Bool
            let locales: [LocaleDescription]
        }

        struct LocaleDescription: Encodable {
            let locale: String
            let description: String?
        }
    }

    struct ASCDescriptionUpdateResult: Encodable {
        let appId: String
        let results: [VersionResult]

        struct VersionResult: Encodable {
            let versionId: String
            let platform: String?
            let updated: [String]
            let skipped: [Skip]
        }

        struct Skip: Encodable {
            let locale: String
            let reason: String
        }
    }

    func getAppStoreMetadata(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        let appId = try resolveASCAppId(args)
        let versions = try await ascVersions(appId: appId, requested: args.string("version_id"))

        var metas: [ASCMetadataResult.VersionMeta] = []
        for version in versions {
            let localizations = try await ascAPI.listLocalizations(versionId: version.id)
            metas.append(ASCMetadataResult.VersionMeta(
                versionId: version.id,
                platform: version.attributes.platform,
                versionString: version.attributes.versionString,
                appStoreState: version.attributes.appStoreState,
                editable: version.isEditable,
                locales: localizations
                    .sorted { $0.attributes.locale < $1.attributes.locale }
                    .map { .init(locale: $0.attributes.locale, description: $0.attributes.description) }
            ))
        }
        return try MCPResultEncoding.result(ASCMetadataResult(appId: appId, versions: metas))
    }

    func updateAppStoreDescription(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        guard let entries = args.objectArray("descriptions"), !entries.isEmpty else {
            throw MCPToolError.missingArgument("descriptions")
        }
        let descriptions: [(locale: String, text: String)] = try entries.map {
            (try $0.requiredString("locale"), try $0.requiredString("description"))
        }

        let appId = try resolveASCAppId(args)
        let targets = try await resolveEditableTargets(appId: appId, requested: args.string("version_id"))

        var results: [ASCDescriptionUpdateResult.VersionResult] = []
        for version in targets {
            let localizationIdByLocale = Dictionary(
                try await ascAPI.listLocalizations(versionId: version.id).map { ($0.attributes.locale, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            var updated: [String] = []
            var skipped: [ASCDescriptionUpdateResult.Skip] = []
            for entry in descriptions {
                guard let localizationId = localizationIdByLocale[entry.locale] else {
                    skipped.append(.init(locale: entry.locale, reason: "no App Store localization for this locale on the version"))
                    continue
                }
                do {
                    try await ascAPI.updateVersionLocalization(id: localizationId, attributes: ["description": AnyEncodable(entry.text)])
                    updated.append(entry.locale)
                } catch {
                    skipped.append(.init(locale: entry.locale, reason: error.localizedDescription))
                }
            }
            results.append(.init(
                versionId: version.id,
                platform: version.attributes.platform,
                updated: updated.sorted(),
                skipped: skipped.sorted { $0.locale < $1.locale }
            ))
        }
        return try MCPResultEncoding.result(ASCDescriptionUpdateResult(appId: appId, results: results))
    }

    // MARK: - Helpers

    private var ascAPI: AppStoreConnectAPIService { .shared }

    private func requireASCConfigured() throws {
        guard AppStoreConnectCredentialsStore.shared.isConfigured else {
            throw MCPToolError.failed("App Store Connect is not configured — add your API key in Settings ▸ App Store Connect, or enable demo mode.")
        }
    }

    private func resolveASCAppId(_ args: MCPArguments) throws -> String {
        if let explicit = args.string("app_id"), !explicit.isEmpty { return explicit }
        if let linked = state.activeProject?.ascAppId, !linked.isEmpty { return linked }
        throw MCPToolError.failed("No App Store Connect app id — pass app_id, or link the active project to an app via the App Store Connect upload wizard.")
    }

    /// All versions to read (a specific one if requested, else every version).
    private func ascVersions(appId: String, requested versionId: String?) async throws -> [ASCAppStoreVersion] {
        let versions = try await ascAPI.listAppStoreVersions(appId: appId)
        if let versionId, !versionId.isEmpty {
            guard let match = versions.first(where: { $0.id == versionId }) else {
                throw MCPToolError.notFound("App Store version \(versionId)")
            }
            return [match]
        }
        guard !versions.isEmpty else {
            throw MCPToolError.failed("App \(appId) has no App Store versions")
        }
        return versions
    }

    /// Versions to write to: the requested one (as-is), else every editable version.
    private func resolveEditableTargets(appId: String, requested versionId: String?) async throws -> [ASCAppStoreVersion] {
        let versions = try await ascAPI.listAppStoreVersions(appId: appId)
        if let versionId, !versionId.isEmpty {
            guard let match = versions.first(where: { $0.id == versionId }) else {
                throw MCPToolError.notFound("App Store version \(versionId)")
            }
            return [match]
        }
        let editable = versions.filter { $0.isEditable }
        guard !editable.isEmpty else {
            throw MCPToolError.failed("App \(appId) has no editable App Store version (a version must be in an editable state such as Prepare for Submission)")
        }
        return editable
    }
}
#endif
