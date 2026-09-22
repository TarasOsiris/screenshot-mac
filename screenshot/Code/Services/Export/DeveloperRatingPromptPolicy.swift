import Foundation

/// Decides when to show the personal "rate us" dialog from the developer — a one-time ask,
/// separate from `ReviewPromptPolicy`'s native `SKStoreReviewController` cadence. That one waits
/// for 3 exports and 14 days and can re-fire every 120 days across versions; this one is a single
/// custom sheet with a photo and a direct App Store link, shown once, right after the 2nd export.
@MainActor
struct DeveloperRatingPromptPolicy {
    static let requiredExportCount = 2

    enum Key {
        static let exportCount = "developerRatingExportCount"
        static let shown = "developerRatingShown"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Counts this export and reports whether the dialog should be shown. Deliberately does *not*
    /// spend the one-time ask — see `markShown()`.
    @discardableResult
    func recordExportAndCheck() -> Bool {
        guard !defaults.bool(forKey: Key.shown) else { return false }

        let count = defaults.integer(forKey: Key.exportCount) + 1
        defaults.set(count, forKey: Key.exportCount)

        return count >= Self.requiredExportCount
    }

    /// Spends the one-time ask, reporting whether this call is what spent it.
    ///
    /// Separate from the check because the sheet is presented on a delay and over a window that
    /// may be closing, or behind a cover SwiftUI won't present across: burning the ask at schedule
    /// time would retire it on a sheet nobody ever saw. Call this when the sheet actually appears.
    @discardableResult
    func markShown() -> Bool {
        guard !defaults.bool(forKey: Key.shown) else { return false }
        defaults.set(true, forKey: Key.shown)
        return true
    }
}
