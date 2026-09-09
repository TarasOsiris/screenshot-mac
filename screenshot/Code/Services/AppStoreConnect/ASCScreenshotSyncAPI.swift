import Foundation

/// The slice of App Store Connect that `AppStoreConnectScreenshotSyncService` actually calls.
///
/// It exists so the sync service can be driven by a fake in tests. Demo mode is not a substitute:
/// it short-circuits the *reads* (`fetchRemoteSet`, `waitForDelivery`, `verify`) but `apply` still
/// issues every write unconditionally, so the idempotency ledger has no other way to be tested
/// without touching a real listing.
@MainActor
protocol ASCScreenshotSyncAPI: AnyObject {
    /// The reserve loop drives its own retries off this rather than the per-call policy.
    var retryPolicy: StoreRetryPolicy { get }

    func listScreenshotSets(localizationId: String, limit: Int) async throws -> [ASCAppScreenshotSet]
    func createScreenshotSet(localizationId: String, displayType: String) async throws -> ASCAppScreenshotSet
    func listScreenshots(setId: String, limit: Int, retryPolicy: StoreRetryPolicy?) async throws -> [ASCAppScreenshot]
    func screenshot(id: String, retryPolicy: StoreRetryPolicy?) async throws -> ASCAppScreenshot
    func listScreenshotOrder(setId: String) async throws -> [String]
    func setScreenshotOrder(setId: String, screenshotIds: [String]) async throws
    func downloadScreenshotData(_ screenshot: ASCAppScreenshot, maxDimension: Int?) async throws -> Data
    func deleteScreenshot(id: String) async throws
    func reserveScreenshot(setId: String, fileName: String, fileSize: Int) async throws -> ASCAppScreenshot
    func uploadChunk(operation: ASCUploadOperation, from fileData: Data) async throws
    func commitScreenshot(id: String, md5Checksum: String) async throws
}

/// The defaults the concrete service declares inline. Repeated here because a protocol requirement
/// can't carry them, and the call sites read better without the noise.
extension ASCScreenshotSyncAPI {
    func listScreenshotSets(localizationId: String) async throws -> [ASCAppScreenshotSet] {
        try await listScreenshotSets(localizationId: localizationId, limit: 50)
    }

    func listScreenshots(setId: String, retryPolicy: StoreRetryPolicy? = nil) async throws -> [ASCAppScreenshot] {
        try await listScreenshots(setId: setId, limit: 50, retryPolicy: retryPolicy)
    }

    func screenshot(id: String) async throws -> ASCAppScreenshot {
        try await screenshot(id: id, retryPolicy: nil)
    }
}

extension AppStoreConnectAPIService: ASCScreenshotSyncAPI {}
