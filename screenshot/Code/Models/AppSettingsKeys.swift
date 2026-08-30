import Foundation

// Lives in `Models/` — the only layer `App/`, `Services/` and `Views/` can all depend on. It
// started in `Views/Settings/`, which is why AppState, ExportFlowModel and ContentView each
// re-declared the same keys (and their defaults) as raw literals.
//
// The raw values are a shipping user's stored preferences: changing one silently resets that
// preference for everyone. AppSettingsKeysTests pins every one of them.
/// Every preference key with its default, declared once. Both settings screens plus ContentView
/// used to re-declare the same `@AppStorage` keys with hand-copied defaults, so a changed default
/// silently disagreed with itself depending on which screen wrote it first.
nonisolated enum AppSettingsKeys {
    static let appearance = "appearance"
    static let appLanguageOverride = "appLanguageOverride"
    static let defaultScreenshotSize = "defaultScreenshotSize"
    static let exportFormat = "exportFormat"
    static let exportCustomSuffix = "exportCustomSuffix"
    static let openExportFolderOnSuccess = "openExportFolderOnSuccess"
    static let defaultTemplateCount = "defaultTemplateCount"
    static let defaultZoomLevel = "defaultZoomLevel"
    static let confirmBeforeDeleting = "confirmBeforeDeleting"
    static let defaultDeviceCategory = "defaultDeviceCategory"
    static let defaultDeviceFrameId = "defaultDeviceFrameId"
    static let projectSortOrder = "projectSortOrder"
    /// The zoom the editor was left at, restored on launch. Distinct from
    /// `defaultZoomLevel`, which is the user's configured starting point.
    static let lastZoomLevel = "lastZoomLevel"
    /// See `DiagnosticsIdentity` — the id a support email carries so its Sentry events are findable.
    static let installId = "installId"
    static let installFirstVersion = "installFirstVersion"
    /// The RevenueCat id already aliased into PostHog. `alias` is an irreversible merge and bills
    /// an event per call, so it fires once per install — see `AnalyticsService.linkStoreUser`.
    static let analyticsAliasedStoreUserId = "analyticsAliasedStoreUserId"
    /// Marks this install as the developer's own so its events can be excluded from every
    /// query. Off by default; nothing reads it but `AnalyticsService.applyInternalUserProfile`.
    static let analyticsInternalUser = "analyticsInternalUser"

    nonisolated enum Default {
        static let appearance = "auto"
        static let defaultScreenshotSize = "1242x2688"
        static let exportFormat = "png"
        static let defaultTemplateCount = 3
        static let defaultZoomLevel = 1.0
        static let confirmBeforeDeleting = true
        static let openExportFolderOnSuccess = true
        static let defaultDeviceCategory = "iphone"
        static let projectSortOrder = "creation"
    }
}
