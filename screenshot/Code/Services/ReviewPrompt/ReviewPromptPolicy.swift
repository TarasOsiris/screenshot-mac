import Foundation

/// Decides when to ask for an App Store review after a success moment (an export or store upload).
///
/// The rules are deliberately conservative — asking too early or too often is worse than not
/// asking — which is exactly why they need a test. This lived in a `ContentView` extension backed
/// by four `@AppStorage` keys, where nothing could reach it.
@MainActor
struct ReviewPromptPolicy {
    static let minSuccessCount = 3
    static let minTimeSinceFirstSuccess: TimeInterval = 14 * 86400
    static let minTimeBetweenPrompts: TimeInterval = 120 * 86400

    /// Raw values predate uploads counting as successes; renaming them would reset every install.
    enum Key {
        static let successCount = "reviewExportCount"
        static let lastPromptedVersion = "reviewLastPromptedVersion"
        static let firstSuccessDate = "reviewFirstExportDate"
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

    var successCount: Int { defaults.integer(forKey: Key.successCount) }

    /// Forgets every success and prompt, as on a fresh install.
    func reset() {
        for key in [Key.successCount, Key.lastPromptedVersion, Key.firstSuccessDate, Key.lastPromptDate] {
            defaults.removeObject(forKey: key)
        }
    }

    func recordSuccess() {
        if defaults.object(forKey: Key.firstSuccessDate) == nil {
            defaults.set(now().timeIntervalSinceReferenceDate, forKey: Key.firstSuccessDate)
        }
        defaults.set(successCount + 1, forKey: Key.successCount)
    }

    /// Spends nothing — only `markPrompted()` does, so an ask that never reaches the screen is free.
    var isPromptDue: Bool {
        // Absence, not zero, is what "never happened" means here. Reading these with
        // `double(forKey:)` made an unset key indistinguishable from the reference date, which
        // only ever worked because a real clock sits ~25 years past it.
        guard !currentVersion.isEmpty,
              currentVersion != (defaults.string(forKey: Key.lastPromptedVersion) ?? ""),
              let firstSuccess = defaults.object(forKey: Key.firstSuccessDate) as? Double
        else { return false }

        let nowStamp = now().timeIntervalSinceReferenceDate
        let lastPrompt = defaults.object(forKey: Key.lastPromptDate) as? Double
        return successCount >= Self.minSuccessCount
            && nowStamp - firstSuccess >= Self.minTimeSinceFirstSuccess
            && lastPrompt.map { nowStamp - $0 >= Self.minTimeBetweenPrompts } ?? true
    }

    /// Spends this version's ask. Call only when the system prompt is actually requested.
    func markPrompted() {
        defaults.set(currentVersion, forKey: Key.lastPromptedVersion)
        defaults.set(now().timeIntervalSinceReferenceDate, forKey: Key.lastPromptDate)
    }
}
