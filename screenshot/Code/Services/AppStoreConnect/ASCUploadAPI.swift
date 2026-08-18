import Foundation

/// The slice of the App Store Connect API the upload/metadata flow uses. Exists so the flow can
/// be driven by a scripted fake in tests instead of the live service — `AppStoreConnectAPIService`
/// already takes an injectable `URLSession`, but the flow reached it through `.shared`.
///
/// Deliberately not the whole client: screenshot set/asset calls belong to
/// `AppStoreConnectScreenshotSyncService`, which owns them already.
/// `Sendable` because `moveToMetadata` starts one of these calls with `async let`, which carries
/// the reference into a child task. Conformers are `@MainActor` classes and so already are.
@MainActor
protocol ASCUploadAPI: Sendable {
    func listAppsWithVersions(limit: Int) async throws -> [ASCAppWithVersions]
    func listAppStoreVersions(appId: String, limit: Int) async throws -> [ASCAppStoreVersion]
    func listLocalizations(versionId: String, limit: Int) async throws -> [ASCAppStoreVersionLocalization]
    func listAppInfos(appId: String) async throws -> [ASCAppInfo]
    func listAppInfoLocalizations(appInfoId: String, limit: Int) async throws -> [ASCAppInfoLocalization]
    func updateVersionLocalization(id: String, attributes: [String: AnyEncodable]) async throws
    func updateAppInfoLocalization(id: String, attributes: [String: AnyEncodable]) async throws
    func updateAppStoreVersion(id: String, attributes: [String: AnyEncodable]) async throws
}

extension AppStoreConnectAPIService: ASCUploadAPI {}

/// Protocol requirements can't carry default arguments, so the concrete service's defaults
/// (200 / 20 / 200 / 200) are restated here rather than at every call site.
extension ASCUploadAPI {
    func listAppsWithVersions() async throws -> [ASCAppWithVersions] {
        try await listAppsWithVersions(limit: 200)
    }

    func listAppStoreVersions(appId: String) async throws -> [ASCAppStoreVersion] {
        try await listAppStoreVersions(appId: appId, limit: 20)
    }

    func listLocalizations(versionId: String) async throws -> [ASCAppStoreVersionLocalization] {
        try await listLocalizations(versionId: versionId, limit: 200)
    }

    func listAppInfoLocalizations(appInfoId: String) async throws -> [ASCAppInfoLocalization] {
        try await listAppInfoLocalizations(appInfoId: appInfoId, limit: 200)
    }
}
