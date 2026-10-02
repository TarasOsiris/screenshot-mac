import Foundation
import StoreKit

/// Asks TestFlight testers to move to the App Store build, so the beta can be wound down.
///
/// TestFlight and App Review both run in the StoreKit sandbox, so the sandbox alone can't tell
/// them apart. The prompt also waits until the running version is live on the App Store: a build
/// under review is always newer than what's live, so reviewers never see it.
@MainActor
struct TestFlightGraduationPolicy {
    /// "Not Now" holds the prompt back for a day rather than forever: the goal is moving everyone.
    static let snoozeInterval: TimeInterval = 24 * 60 * 60

    enum Key {
        static let lastShown = "testFlightGraduationLastShown"
    }

    let defaults: UserDefaults
    let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    var isDue: Bool {
        guard let last = defaults.object(forKey: Key.lastShown) as? Date else { return true }
        return now().timeIntervalSince(last) >= Self.snoozeInterval
    }

    func markShown() {
        defaults.set(now(), forKey: Key.lastShown)
    }

    /// Shared so every scene (iPad windows, a reopened Mac window) reuses one check per launch.
    static let shouldPromptThisLaunch = Task { await TestFlightGraduationPolicy().shouldPrompt() }

    func shouldPrompt() async -> Bool {
        #if DEBUG || DIRECT_DISTRIBUTION
        return false
        #else
        guard isDue, await Self.isTestFlightBuild(),
              let liveVersion = await Self.liveAppStoreVersion() else { return false }
        return Self.isReleased(running: Bundle.main.shortVersion, liveVersion: liveVersion)
        #endif
    }

    static func isReleased(running: String, liveVersion: String) -> Bool {
        guard !running.isEmpty else { return false }
        return liveVersion.compare(running, options: .numeric) != .orderedAscending
    }

    private static func isTestFlightBuild() async -> Bool {
        // Unverified is fine: this only decides whether to show a dialog.
        guard let transaction = try? await AppTransaction.shared else { return false }
        return transaction.unsafePayloadValue.environment == .sandbox
    }

    /// iOS and macOS have separate version trains; `desktopSoftware` selects the Mac listing.
    #if os(macOS)
    private static let lookupEntity = "&entity=desktopSoftware"
    #else
    private static let lookupEntity = ""
    #endif

    private static var lookupURL: URL? {
        URL(string: "https://itunes.apple.com/lookup?id=\(AppLinks.appStoreID)\(lookupEntity)")
    }

    private struct LookupResponse: Decodable {
        struct Result: Decodable { let version: String }
        let results: [Result]
    }

    private static func liveAppStoreVersion() async -> String? {
        guard let lookupURL else { return nil }
        var request = URLRequest(url: lookupURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(LookupResponse.self, from: data) else { return nil }
        return response.results.first?.version
    }
}
