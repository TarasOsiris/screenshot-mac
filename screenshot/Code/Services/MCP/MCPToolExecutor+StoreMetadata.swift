#if os(macOS)
import Foundation
import MCP

struct MCPLocalizationWriteResult: Encodable {
    var versionId: String?
    var platform: String?
    var updated: [String] = []
    var skipped: [MCPToolExecutor.ASCDescriptionUpdateResult.Skip] = []
}

struct MCPMetadataUpdateResult: Encodable {
    let appId: String
    let versions: [MCPLocalizationWriteResult]
    let appInfo: MCPLocalizationWriteResult?
}

struct MCPStoreAppItem: Encodable {
    let id: String
    let name: String
    let bundleId: String
    let linkedProjectIds: [String]?
}

extension MCPToolExecutor {

    /// Checked up front so one over-long locale can't half-apply an update.
    private static let metadataFields: [(key: String, attribute: String, limit: Int?, appInfo: Bool)] = [
        ("description", "description", 4000, false),
        ("keywords", "keywords", 100, false),
        ("promotional_text", "promotionalText", 170, false),
        ("whats_new", "whatsNew", 4000, false),
        ("marketing_url", "marketingUrl", nil, false),
        ("support_url", "supportUrl", nil, false),
        ("name", "name", 30, true),
        ("subtitle", "subtitle", 30, true),
        ("privacy_policy_url", "privacyPolicyUrl", nil, true),
    ]

    func updateAppStoreMetadata(_ args: MCPArguments) async throws -> CallTool.Result {
        try requireASCConfigured()
        guard let entries = try args.strictObjectArray("locales"), !entries.isEmpty else {
            throw MCPToolError.missingArgument("locales")
        }
        var versionChanges: [String: [String: AnyEncodable]] = [:]
        var appInfoChanges: [String: [String: AnyEncodable]] = [:]
        for (index, entry) in entries.enumerated() {
            let locale = try entry.requiredString("locale")
            for field in Self.metadataFields {
                guard let value = entry.string(field.key) else { continue }
                if let limit = field.limit, value.count > limit {
                    throw MCPToolError.invalidArgument("locales[\(index)].\(field.key)", "\(locale) is \(value.count) characters; App Store Connect allows \(limit)")
                }
                if field.appInfo {
                    appInfoChanges[locale, default: [:]][field.attribute] = AnyEncodable(value)
                } else {
                    versionChanges[locale, default: [:]][field.attribute] = AnyEncodable(value)
                }
            }
        }

        let appId = try resolveASCAppId(fromAppIdOrProject: args)
        let versions = versionChanges.isEmpty ? [] : try await writeVersionChanges(versionChanges, appId: appId, versionId: args.string("version_id"))
        var appInfo: MCPLocalizationWriteResult?
        if !appInfoChanges.isEmpty {
            let ids = Self.localizationIds(try await AppStoreConnectVersionMetadata.editableAppInfoLocalizations(ascAPI, appId: appId).map { ($0.attributes.locale, $0.id) })
            appInfo = await applyLocalizationChanges(appInfoChanges, to: ids, missing: "no app info localization for this locale") { [ascAPI] id, changes in
                try await ascAPI.updateAppInfoLocalization(id: id, attributes: changes)
            }
        }
        return try MCPResultEncoding.result(MCPMetadataUpdateResult(appId: appId, versions: versions, appInfo: appInfo))
    }

    /// Writes per-locale changes to every editable version (or just `versionId`).
    func writeVersionChanges(
        _ changes: [String: [String: AnyEncodable]],
        appId: String,
        versionId: String?
    ) async throws -> [MCPLocalizationWriteResult] {
        var results: [MCPLocalizationWriteResult] = []
        for version in try await resolveEditableTargets(appId: appId, requested: versionId) {
            let ids = Self.localizationIds(try await ascAPI.listLocalizations(versionId: version.id).map { ($0.attributes.locale, $0.id) })
            var result = await applyLocalizationChanges(changes, to: ids, missing: "no localization for this locale on the version") { [ascAPI] id, changes in
                try await AppStoreConnectVersionMetadata.patchLocalization(ascAPI, id: id, changes: changes)
            }
            result.versionId = version.id
            result.platform = version.attributes.platform
            results.append(result)
        }
        return results
    }

    private static func localizationIds(_ pairs: [(String, String)]) -> [String: String] {
        Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// Writes each locale a few at a time; one rejected locale is reported, not fatal.
    private func applyLocalizationChanges(
        _ changesByLocale: [String: [String: AnyEncodable]],
        to localizationIds: [String: String],
        missing: String,
        write: @escaping @MainActor (String, [String: AnyEncodable]) async throws -> Void
    ) async -> MCPLocalizationWriteResult {
        var result = MCPLocalizationWriteResult()
        // `@MainActor` element type, as in the wizard's save: `AnyEncodable` is not Sendable.
        var writes: [@MainActor () async -> (locale: String, error: String?)] = []
        for (locale, changes) in changesByLocale.sorted(by: { $0.key < $1.key }) {
            guard let id = localizationIds[locale] else {
                result.skipped.append(.init(locale: locale, reason: missing))
                continue
            }
            writes.append {
                do {
                    try await write(id, changes)
                    return (locale, nil)
                } catch {
                    return (locale, error.localizedDescription)
                }
            }
        }
        await withTaskGroup(of: (locale: String, error: String?).self) { group in
            var pending = writes.makeIterator()
            for _ in 0..<AppStoreConnectVersionMetadata.writeConcurrency {
                guard let write = pending.next() else { break }
                group.addTask { await write() }
            }
            while let finished = await group.next() {
                if let error = finished.error {
                    result.skipped.append(.init(locale: finished.locale, reason: error))
                } else {
                    result.updated.append(finished.locale)
                }
                guard let write = pending.next() else { continue }
                group.addTask { await write() }
            }
        }
        result.updated.sort()
        result.skipped.sort { $0.locale < $1.locale }
        return result
    }

    func listAppStoreApps() async throws -> CallTool.Result {
        try requireASCConfigured()
        let linked = Dictionary(grouping: state.visibleProjects, by: \.ascAppId)
        let apps = try await ascAPI.listApps().map { app in
            MCPStoreAppItem(
                id: app.id,
                name: app.attributes.name,
                bundleId: app.attributes.bundleId,
                linkedProjectIds: linked[app.id].map { $0.map(\.id.uuidString) }
            )
        }
        return try MCPResultEncoding.result(["apps": apps])
    }

    /// Links (or with null, unlinks) a project to its App Store Connect app and Google Play package.
    func linkProjectStores(_ args: MCPArguments) throws -> CallTool.Result {
        let project = try requireProject(args)
        let linksApp = args.isPresent("app_id")
        let linksPackage = args.isPresent("play_package_name")
        guard linksApp || linksPackage else {
            throw MCPToolError.missingArgument("app_id or play_package_name")
        }
        let appId = args.string("app_id").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let package = args.string("play_package_name").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Validated before either link changes, so a rejected call leaves the project as it was.
        if let package, !package.isEmpty, !GooglePlayUploadValidator.isValidPackageName(package) {
            throw MCPToolError.invalidArgument("play_package_name", "\(package) is not a valid application id, e.g. com.example.app")
        }
        if linksApp {
            state.setASCAppId(appId.flatMap { $0.isEmpty ? nil : $0 }, forProject: project.id)
        }
        if linksPackage {
            state.setGooglePlayPackageName(package.flatMap { $0.isEmpty ? nil : $0 }, forProject: project.id)
        }
        return try listProjects()
    }
}
#endif
