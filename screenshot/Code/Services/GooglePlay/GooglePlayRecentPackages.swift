import Foundation

/// The package names the Google Play wizard offers in its recents menu.
///
/// Play has no app-listing endpoint, so the package field can never become a picker over the
/// developer's apps the way App Store Connect's app step is. Remembering what has been typed
/// before is the closest equivalent that doesn't lie about what the API can do.
nonisolated enum GooglePlayRecentPackages {
    static let limit = 5

    static func load(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: AppSettingsKeys.googlePlayRecentPackageNames) ?? []
    }

    /// Moves `packageName` to the front, de-duplicated, and trims the list to `limit`.
    static func remember(_ packageName: String, defaults: UserDefaults = .standard) {
        let trimmed = packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var names = load(defaults: defaults).filter { $0 != trimmed }
        names.insert(trimmed, at: 0)
        defaults.set(Array(names.prefix(limit)), forKey: AppSettingsKeys.googlePlayRecentPackageNames)
    }
}
