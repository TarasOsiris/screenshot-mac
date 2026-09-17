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
    /// macOS: the inspector follows the selection (row or shapes) instead of always showing the
    /// row, and the bottom properties bar steps aside while it does. Off by default while the layout is new.
    static let selectionInspector = "selectionInspectorEnabled"
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
    /// The internal-user value already published to PostHog. `setPersonProperties` sends a
    /// billed `$set` event and only dedups within a process, so without this the flag would
    /// cost one event per launch forever — see `AnalyticsService.applyInternalUserProfile`.
    static let analyticsAppliedInternalUser = "analyticsAppliedInternalUser"
    /// Package names the Google Play wizard has uploaded to, newest first. Kept across projects —
    /// one developer's apps are usually the same handful — where the per-project
    /// `savedGooglePlayPackageName` only prefills the project it belongs to.
    static let googlePlayRecentPackageNames = "googlePlayRecentPackageNames"

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
        static let selectionInspector = false
    }
}

/// A collapsible inspector section, and the key its expansion persists under.
///
/// The raw values are the keys 4.16 shipped as inline literals across the three inspector views —
/// changing one silently re-expands that section for everyone, so `AppSettingsKeysTests` pins them.
/// Single- and multi-selection deliberately share five sections; as literals that was a string
/// match nothing enforced, and as cases it is the same value by construction.
nonisolated enum InspectorSectionID: String, CaseIterable {
    case rowSize = "inspectorSizeExpanded"
    case rowDevice = "inspectorDeviceExpanded"
    case rowBackground = "inspectorBackgroundExpanded"
    case rowShapes = "inspectorShapesExpanded"
    case rowVisibility = "inspectorVisibilityExpanded"
    case rowOther = "inspectorOtherExpanded"
    case shapeGeometry = "inspectorShapeGeometryExpanded"
    case shapeDevice = "inspectorShapeDeviceExpanded"
    case shape3D = "inspectorShape3DExpanded"
    case shapeText = "inspectorShapeTextExpanded"
    case shapeTextBackground = "inspectorShapeTextBackgroundExpanded"
    case shapeMedia = "inspectorShapeMediaExpanded"
    case shapeAppearance = "inspectorShapeAppearanceExpanded"
    case shapeFill = "inspectorShapeFillExpanded"
    case shapeOutline = "inspectorShapeOutlineExpanded"
    case shapeShadow = "inspectorShapeShadowExpanded"
    case shapeLocalization = "inspectorShapeLocalizationExpanded"

    /// Secondary and experimental sections start closed, as they shipped.
    var startsExpanded: Bool {
        switch self {
        case .shape3D, .shapeTextBackground: false
        default: true
        }
    }
}
