import Foundation

/// Decides when to ask for an App Store review after an export.
///
/// The rules are deliberately conservative — asking too early or too often is worse than not
/// asking — which is exactly why they need a test. This lived in a `ContentView` extension backed
/// by four `@AppStorage` keys, where nothing could reach it.
@MainActor
struct ReviewPromptPolicy {
    static let minExportCount = 3
    static let minTimeSinceFirstExport: TimeInterval = 14 * 86400
    static let minTimeBetweenPrompts: TimeInterval = 120 * 86400

    enum Key {
        static let exportCount = "reviewExportCount"
        static let lastPromptedVersion = "reviewLastPromptedVersion"
        static let firstExportDate = "reviewFirstExportDate"
        static let lastPromptDate = "reviewLastPromptDate"
    }

    let defaults: UserDefaults
    let currentVersion: String
    /// Injected so a test can move through the 14- and 120-day windows without waiting.
    let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        currentVersion: String = Bundle.main.shortVersion,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.now = now
    }

    /// Counts this export and reports whether the prompt should be shown. Records the prompt when
    /// it returns true, so a caller that ignores the result silently burns the opportunity.
    @discardableResult
    func recordExportAndCheck() -> Bool {
        guard !currentVersion.isEmpty,
              currentVersion != (defaults.string(forKey: Key.lastPromptedVersion) ?? "") else { return false }

        let nowStamp = now().timeIntervalSinceReferenceDate

        // Absence, not zero, is what "never happened" means here. Reading these with
        // `double(forKey:)` made an unset key indistinguishable from the reference date, which
        // only ever worked because a real clock sits ~25 years past it.
        let firstExport = defaults.object(forKey: Key.firstExportDate) as? Double ?? {
            defaults.set(nowStamp, forKey: Key.firstExportDate)
            return nowStamp
        }()
        let lastPrompt = defaults.object(forKey: Key.lastPromptDate) as? Double

        let count = defaults.integer(forKey: Key.exportCount) + 1
        defaults.set(count, forKey: Key.exportCount)

        guard count >= Self.minExportCount,
              nowStamp - firstExport >= Self.minTimeSinceFirstExport,
              lastPrompt.map({ nowStamp - $0 >= Self.minTimeBetweenPrompts }) ?? true
        else { return false }

        defaults.set(currentVersion, forKey: Key.lastPromptedVersion)
        defaults.set(nowStamp, forKey: Key.lastPromptDate)
        return true
    }
}
