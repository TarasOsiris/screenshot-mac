import Foundation
import CoreGraphics

/// In-memory mock data for App Store Connect demo mode. The catalog is **derived
/// from the active project** so the upload wizard always finds a matching App Store
/// version (correct platform) and a matching locale for every project locale —
/// regardless of which project the user opens. Writes (create / update / upload /
/// commit) are local mutations so the wizard runs end-to-end without touching
/// Apple's servers. App Review can flip on demo mode and walk through the entire
/// flow without an API key.
final class AppStoreConnectDemoData: @unchecked Sendable {
    static let shared = AppStoreConnectDemoData()

    private static let appId = "demo-app-1"
    private static let appInfoId = "demo-appinfo-1"
    private static let baseLocale = "en-US"

    private let lock = NSLock()

    /// Locales the wizard should be able to match. Seeded from the active project
    /// (plus a base locale fallback) when the upload sheet opens.
    private var contextLocaleCodes: [String] = [baseLocale]

    /// Platforms the demo offers a version for. Seeded from the row sizes of the
    /// active project so the auto-selected version's `ascPlatform` lines up with
    /// the user's display types.
    private var contextPlatforms: [ASCPlatform] = [.ios]

    private var screenshotSetsByLocalization: [String: [ASCAppScreenshotSet]] = [:]
    private var idCounter = 0

    /// Reseeds the demo catalog so the wizard always offers a matching version
    /// platform and a matching locale for the project the user is uploading.
    /// Call once when the upload sheet opens (and again on Refresh).
    func updateContext(localeCodes: [String], rowSizes: [CGSize]) {
        let detected = rowSizes.compactMap { size in
            ASCDisplayType.detect(width: size.width, height: size.height)
        }
        let inferred = detected.flatMap { $0.allowedPlatforms }
        var platforms = uniquePreservingOrder(inferred)
        if platforms.isEmpty { platforms = [.ios] }

        var codes = [Self.baseLocale]
        for code in localeCodes where !codes.contains(code) {
            codes.append(code)
        }

        lock.lock(); defer { lock.unlock() }
        contextPlatforms = platforms
        contextLocaleCodes = codes
        // Reset upload state so re-opening the sheet starts from a clean slate.
        screenshotSetsByLocalization = [:]
        idCounter = 0
    }

    var apps: [ASCApp] {
        [
            ASCApp(
                id: Self.appId,
                attributes: ASCApp.Attributes(
                    name: "Screenshot Bro Demo",
                    bundleId: "xyz.tleskiv.screenshot",
                    sku: "DEMO-SKU-1",
                    primaryLocale: Self.baseLocale
                )
            )
        ]
    }

    func versions(forApp appId: String) -> [ASCAppStoreVersion] {
        guard appId == Self.appId else { return [] }
        let platforms = lockedRead { contextPlatforms }
        return platforms.map { platform in
            ASCAppStoreVersion(
                id: Self.versionId(for: platform),
                attributes: ASCAppStoreVersion.Attributes(
                    versionString: "1.0.0",
                    appStoreState: "PREPARE_FOR_SUBMISSION",
                    platform: platform.rawValue,
                    copyright: "© 2026 Demo Inc."
                )
            )
        }
    }

    func versionLocalizations(forVersion versionId: String) -> [ASCAppStoreVersionLocalization] {
        guard versionId.hasPrefix("demo-version-") else { return [] }
        let codes = lockedRead { contextLocaleCodes }
        return codes.map { code in
            ASCAppStoreVersionLocalization(
                id: "demo-vloc-\(versionId)-\(code)",
                attributes: ASCAppStoreVersionLocalization.Attributes(
                    locale: code,
                    description: "Demo description for \(code).",
                    keywords: "demo, screenshots, app store",
                    promotionalText: "Demo promo text.",
                    whatsNew: "Demo release notes.",
                    marketingUrl: "https://example.com/marketing",
                    supportUrl: "https://example.com/support"
                )
            )
        }
    }

    func appInfos(forApp appId: String) -> [ASCAppInfo] {
        guard appId == Self.appId else { return [] }
        return [
            ASCAppInfo(
                id: Self.appInfoId,
                attributes: ASCAppInfo.Attributes(
                    state: "PREPARE_FOR_SUBMISSION",
                    appStoreState: "PREPARE_FOR_SUBMISSION"
                )
            )
        ]
    }

    func appInfoLocalizations(forAppInfo appInfoId: String) -> [ASCAppInfoLocalization] {
        guard appInfoId == Self.appInfoId else { return [] }
        let codes = lockedRead { contextLocaleCodes }
        return codes.map { code in
            ASCAppInfoLocalization(
                id: "demo-ailoc-\(code)",
                attributes: ASCAppInfoLocalization.Attributes(
                    locale: code,
                    name: "Screenshot Bro Demo",
                    subtitle: "App Review demo build",
                    privacyPolicyUrl: "https://example.com/privacy"
                )
            )
        }
    }

    func screenshotSets(localizationId: String) -> [ASCAppScreenshotSet] {
        lockedRead { screenshotSetsByLocalization[localizationId] ?? [] }
    }

    func createScreenshotSet(localizationId: String, displayType: String) -> ASCAppScreenshotSet {
        lock.lock(); defer { lock.unlock() }
        let set = ASCAppScreenshotSet(
            id: nextIdLocked(prefix: "demo-set"),
            attributes: ASCAppScreenshotSet.Attributes(screenshotDisplayType: displayType)
        )
        screenshotSetsByLocalization[localizationId, default: []].append(set)
        return set
    }

    func deleteScreenshotSet(id: String) {
        lock.lock(); defer { lock.unlock() }
        for (loc, sets) in screenshotSetsByLocalization {
            screenshotSetsByLocalization[loc] = sets.filter { $0.id != id }
        }
    }

    func reserveScreenshot(setId _: String, fileName: String, fileSize: Int) -> ASCAppScreenshot {
        lock.lock(); defer { lock.unlock() }
        return ASCAppScreenshot(
            id: nextIdLocked(prefix: "demo-shot"),
            attributes: ASCAppScreenshot.Attributes(
                fileName: fileName,
                fileSize: fileSize,
                uploaded: false,
                sourceFileChecksum: nil,
                uploadOperations: []
            )
        )
    }

    private static func versionId(for platform: ASCPlatform) -> String {
        "demo-version-\(platform.rawValue)"
    }

    private func lockedRead<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private func nextIdLocked(prefix: String) -> String {
        idCounter += 1
        return "\(prefix)-\(idCounter)"
    }

    private func uniquePreservingOrder<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for item in items where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }
}
