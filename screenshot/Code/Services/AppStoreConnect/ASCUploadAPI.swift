import Foundation

/// The slice of the App Store Connect API the upload/metadata flow uses. Exists so the flow can
/// be driven by a scripted fake in tests instead of the live service — `AppStoreConnectAPIService`
/// already takes an injectable `URLSession`, but the flow reached it through `.shared`.
///
/// Deliberately not the whole client: screenshot set/asset calls belong to
/// `AppStoreConnectScreenshotSyncService`, which owns them already.
@MainActor
protocol ASCUploadAPI {
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
