import Foundation

/// The identity a support email can carry so its Sentry events are findable.
///
/// Sentry's own per-install id lives in the SDK cache directory and is `@_spi(Private)`, so it is
/// neither durable across a cache purge nor readable to show the user. Owning the id here also
/// fixes a split: `setUser` used to run only once RevenueCat had configured, so every launch
/// emitted SDK-id events before that point and RevenueCat-id events after — one install, two
/// `user.id` values, and "users affected" counted twice.
nonisolated enum DiagnosticsIdentity {
    /// Stable per-install random UUID. Not derived from the device or the user — it exists to match
    /// an emailed report to the events we already received. Sentry's `user.id` and PostHog's
    /// `distinct_id` are both this value, so one install reads as one person in both.
    static let installId: String = {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: AppSettingsKeys.installId), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: AppSettingsKeys.installId)
        defaults.set(Bundle.main.shortVersion, forKey: AppSettingsKeys.installFirstVersion)
        return created
    }()

    /// The version this install first ran, so a crash says "fresh install" or "upgraded from 3.x".
    /// Absent for installs that predate this key.
    static var firstVersion: String? {
        UserDefaults.standard.string(forKey: AppSettingsKeys.installFirstVersion)
    }
}
