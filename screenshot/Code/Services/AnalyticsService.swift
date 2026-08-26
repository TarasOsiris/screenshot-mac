import Foundation
import PostHog

/// Product analytics: how far installs get through onboarding, project creation, export and
/// purchase. Deliberately shaped like `CrashReportingService` — same XCTest gate, same
/// "counts and enum names only" contract, and `import PostHog` confined here so call sites
/// stay SDK-agnostic.
///
/// The split with Sentry is: a breadcrumb is only ever read attached to a crash, an event here
/// is read in aggregate. Neither may carry project, row, locale or user text.
nonisolated enum AnalyticsService {
    private static let host = "https://us.i.posthog.com"
    private static let apiKeyEnvironmentName = "POSTHOG_API_KEY"
    private static let apiKeyInfoDictionaryKey = "POSTHOG_API_KEY"
    private static let debugOptInEnvironmentName = "SCREENSHOT_ENABLE_ANALYTICS"

    /// Cached once, for the same reason `CrashReportingService.isReportingEnabled` is:
    /// `isRunningUnderXCTest` rebuilds the process environment on every read.
    ///
    /// Debug builds are silent: every local run would otherwise land in the production project as
    /// a real install, and a day of development would out-weigh a day of real users in every
    /// funnel. Sentry can afford to stay on in debug because it only speaks up when something
    /// breaks; an analytics event fires when things go *right*, which is most of the time.
    /// Set `SCREENSHOT_ENABLE_ANALYTICS=1` to opt a local build back in for verification — that
    /// override is checked *after* the test guard, deliberately, so a developer who leaves it set
    /// in the scheme still can't make a test run transmit.
    static let isEnabled: Bool = {
        guard !PersistenceService.isRunningUnderXCTest else { return false }
        #if DEBUG
        return ProcessInfo.processInfo.environment[debugOptInEnvironmentName] == "1"
        #else
        return true
        #endif
    }()

    /// Whether `setup` actually ran. `screenshotTests` is a hosted target, so the app really
    /// launches during a test run — this is what proves nothing can be transmitted from one.
    static var isActive: Bool { didSetUpLock.withLock { didSetUp } }

    private static let didSetUpLock = NSLock()
    private nonisolated(unsafe) static var didSetUp = false

    /// Raw value is the PostHog event name. Adding a case is how you get a new event, and the
    /// enum is the published list — `privacy.tsx` documents exactly these.
    enum Event: String, CaseIterable {
        case appLaunched = "app_launched"

        case onboardingStarted = "onboarding_started"
        case onboardingStepViewed = "onboarding_step_viewed"
        case onboardingCompleted = "onboarding_completed"
        case onboardingSkipped = "onboarding_skipped"

        case projectCreated = "project_created"
        case projectDeleted = "project_deleted"
        case templateApplied = "template_applied"
        case screenshotsImported = "screenshots_imported"
        case localeAdded = "locale_added"
        case translationRun = "translation_run"

        case exportStarted = "export_started"
        case exportFinished = "export_finished"
        case exportFailed = "export_failed"
        case exportRouted = "export_routed"
        case exportAbandoned = "export_abandoned"

        case storeUploadFinished = "store_upload_finished"
        case storeUploadFailed = "store_upload_failed"

        case paywallShown = "paywall_shown"
        case paywallDismissed = "paywall_dismissed"
        case purchaseCompleted = "purchase_completed"
        case purchaseFailed = "purchase_failed"
        case purchaseRestored = "purchase_restored"

        case mcpServerToggled = "mcp_server_toggled"
        case mcpServerStarted = "mcp_server_started"
        case mcpServerStartFailed = "mcp_server_start_failed"
        case mcpSessionStarted = "mcp_session_started"
        case mcpSessionFinished = "mcp_session_finished"
        case mcpToolCalled = "mcp_tool_called"
    }

    /// Raw value is the PostHog `$screen_name`. A screen is a **window or a full-surface modal** —
    /// something you can meaningfully be "on". Never a popover, alert, confirmation dialog,
    /// inspector, or inline panel: those are interactions, and instrumenting them would re-create
    /// by hand the swizzled autocapture `start()` deliberately turns off.
    ///
    /// Adding a case is how you get a new screen, and the `CaseIterable` enum is the published
    /// list — `privacy.tsx` §6 documents exactly these, so a new case means a policy edit.
    enum Screen: String, CaseIterable {
        case editor
        case noProject = "no_project"
        case newProject = "new_project"
        case projects
        case settings
        case help

        case onboarding
        case paywall
        case purchaseCelebration = "purchase_celebration"

        case exportDestination = "export_destination"
        case showcaseExport = "showcase_export"
        case ascUpload = "asc_upload"
        case ascMetadata = "asc_metadata"
        case googlePlayUpload = "google_play_upload"

        case manageLocales = "manage_locales"
        case translationOverview = "translation_overview"
    }

    /// Property keys are an enum, not `String`, so no call site *can* pass a project name, row
    /// label, locale label, file name or user-written text. That is the whole point of the type.
    enum Property: String {
        case appVersion = "app_version"
        case appBuild = "app_build"
        case firstVersion = "first_version"
        case platform
        case isDebug = "is_debug"
        case pro
        case storage
        case mcpEnabled = "mcp_enabled"
        case storeUserId = "rc_user_id"

        case source
        case deferred
        case step
        case lastStep = "last_step"
        case wasActive = "was_active"
        case templateId = "template_id"
        case rowCount = "row_count"
        case templateCount = "template_count"
        case localeCount = "locale_count"
        case shapeCount = "shape_count"
        case imageCount = "image_count"
        case count
        case detectedDevice = "detected_device"
        case result
        case format
        case destination
        case durationMs = "duration_ms"
        case cancelled
        case written
        case store
        case trigger
        case productId = "product_id"
        case tier
        case tool
        case mcpSessionId = "mcp_session_id"
        case toolCallCount = "tool_call_count"
        case distinctToolCount = "distinct_tool_count"
        case enabled
        case ok
        case userCancelled = "user_cancelled"
    }

    /// The only keys allowed to carry a `String`. Every one is our own vocabulary — an enum raw
    /// value, a bundled template id, an MCP tool name, a version string. Anything else with a
    /// string value is dropped in `beforeSend`, which is what makes "never user content" a
    /// property of the code rather than of everyone remembering.
    private static let textualProperties: Set<Property> = [
        .appVersion, .appBuild, .firstVersion, .platform, .storage, .storeUserId,
        .source, .step, .lastStep, .templateId, .detectedDevice, .result,
        .format, .destination, .store, .trigger, .productId, .tier, .tool,
        .mcpSessionId,
    ]

    // MARK: - Lifecycle

    static func start() {
        guard isEnabled, !isActive else { return }

        guard let apiKey = resolvedAPIKey() else {
            // A shipped build with no key reports nothing, forever, silently — a packaging bug.
            CrashReportingService.report(.analyticsConfigurationInvalid, extra: ["reason": "missingAPIKey"])
            return
        }

        let config = PostHogConfig(projectToken: apiKey, host: host)

        // The one autocapture worth having: install / update / open / background, so a funnel has
        // a denominator. It is the only integration that doesn't need swizzling.
        config.captureApplicationLifecycleEvents = true

        // Every swizzled integration PostHog installs by default captures interactions — element
        // taps carrying the control's title, screen views, push tokens. That is the "stream of
        // usage events" the privacy policy rules out, and the titles are user-facing text.
        config.enableSwizzling = false
        config.captureScreenViews = false
        #if os(iOS) || os(macOS)
        config.capturePushNotificationSubscriptions = false
        config.capturePushNotificationOpened = false
        #endif
        #if os(iOS)
        config.captureElementInteractions = false
        config.sessionReplay = false
        if #available(iOS 15.0, *) {
            config.surveys = false
        }
        #endif

        // No flags or experiments in use; both defaults put a request on the launch path.
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false

        // MUST stay false. It installs Mach exception, POSIX signal and NSException handlers via
        // PostHog's vendored PLCrashReporter, which would fight SentryCrash for the same hooks —
        // and crash reporting is the one signal we cannot afford to lose. Sentry owns crashes.
        config.errorTrackingConfig.autoCapture = false

        config.setBeforeSend { event in scrubbed(event) }

        #if DEBUG
        // Only reachable via the opt-in above, and then the SDK's own logging is what you want.
        config.debug = true
        #endif

        PostHogSDK.shared.setup(config)
        didSetUpLock.withLock { didSetUp = true }

        // Before any capture, and before RevenueCat exists: `distinct_id` is the same value as
        // Sentry's `user.id`, so one install is one person in both tools. Also what lets
        // `linkStoreUser` alias later without reassigning identity.
        PostHogSDK.shared.identify(DiagnosticsIdentity.installId)
        PostHogSDK.shared.register(launchProperties())
    }

    private static func launchProperties() -> [String: Any] {
        var properties: [String: Any] = [
            Property.appVersion.rawValue: Bundle.main.shortVersion,
            Property.appBuild.rawValue: Bundle.main.buildNumber,
            // Server-side GeoIP resolves this into a location we have no use for, and Sentry is
            // already configured not to receive an IP — keeping the two consistent avoids
            // explaining two different postures in the privacy policy.
            "$ip": "0.0.0.0",
        ]
        #if os(macOS)
        properties[Property.platform.rawValue] = "macos"
        #else
        properties[Property.platform.rawValue] = "ipados"
        #endif
        #if DEBUG
        properties[Property.isDebug.rawValue] = true
        #else
        properties[Property.isDebug.rawValue] = false
        #endif
        if let firstVersion = DiagnosticsIdentity.firstVersion {
            properties[Property.firstVersion.rawValue] = firstVersion
        }
        return properties
    }

    // MARK: - Capture

    static func capture(_ event: Event, _ properties: [Property: Any] = [:]) {
        guard isEnabled, isActive else { return }
        PostHogSDK.shared.capture(event.rawValue, properties: wireProperties(properties))
    }

    /// Records a `$screen` view — the native equivalent of a pageview, and the only navigation
    /// signal PostHog gets from a native app (`$pageview` is a web-SDK event and will never
    /// appear here). Reported from the `.screenView(_:restoring:)` modifier, never inline.
    ///
    /// Manual `screen()` is unaffected by `captureScreenViews`/`enableSwizzling` staying `false`:
    /// those govern only the swizzled `viewDidAppear` autocapture, which observes interactions.
    ///
    /// Side effect worth knowing: the SDK caches the name and stamps `$screen_name` onto every
    /// *later* event, which is what gives `export_started` and friends a "where did this happen"
    /// dimension for free — and why a modal must re-report its host screen when it closes, or the
    /// stamp stays stuck on a sheet the user already dismissed.
    static func screen(_ screen: Screen) {
        guard isEnabled, isActive else { return }
        PostHogSDK.shared.screen(screen.rawValue)
    }

    /// Person-level attributes that describe the install rather than a moment in it. Mirrors the
    /// Sentry tags set at the same call sites, so the two never disagree about one install.
    static func setProfile(_ properties: [Property: Any]) {
        guard isEnabled, isActive, !properties.isEmpty else { return }
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: wireProperties(properties))
    }

    /// Attaches the RevenueCat id as a *second* `distinct_id` on the same person, so purchase data
    /// keyed on it joins to the funnel.
    ///
    /// `alias` adds an id and leaves the current `distinct_id` alone — which is why it is safe here
    /// and `identify(appUserID)` would not be. RevenueCat configures well after launch, so
    /// re-identifying would fork one install across two ids per run: the Sentry bug fixed in
    /// `fde474e1`, generalised. The merge is irreversible and bills an event, so it fires once per
    /// install, or again only if RevenueCat hands back a different id.
    static func linkStoreUser(_ appUserID: String?) {
        guard isEnabled, isActive,
              let appUserID, !appUserID.isEmpty,
              UserDefaults.standard.string(forKey: AppSettingsKeys.analyticsAliasedStoreUserId) != appUserID
        else { return }

        PostHogSDK.shared.alias(appUserID)
        setProfile([.storeUserId: appUserID])
        UserDefaults.standard.set(appUserID, forKey: AppSettingsKeys.analyticsAliasedStoreUserId)
    }

    /// Drains the queue. Worth calling where the process may not come back — app termination.
    static func flush() {
        guard isEnabled, isActive else { return }
        PostHogSDK.shared.flush()
    }

    // MARK: - Property hygiene

    private static func wireProperties(_ properties: [Property: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) })
    }

    /// Second line of defence behind the `Property` enum: drop any string-valued property whose key
    /// isn't in the allowlist. The SDK's own `$`-prefixed context (device model, OS, locale) is
    /// device metadata, not user content, and passes through.
    ///
    /// Split from `scrubbed` so the policy is testable without constructing an SDK type — keeping
    /// `import PostHog` out of the test target is the point of the whole façade.
    static func allowsProperty(key: String, value: Any) -> Bool {
        guard value is String, !key.hasPrefix("$") else { return true }
        guard let property = Property(rawValue: key) else { return false }
        return textualProperties.contains(property)
    }

    private static func scrubbed(_ event: PostHogEvent) -> PostHogEvent {
        event.properties = event.properties.filter(allowsProperty(key:value:))
        return event
    }

    // MARK: - Configuration

    private static func resolvedAPIKey() -> String? {
        let environmentKey = ProcessInfo.processInfo.environment[apiKeyEnvironmentName]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentKey, !environmentKey.isEmpty {
            return environmentKey
        }

        let infoDictionaryKey = (Bundle.main.object(forInfoDictionaryKey: apiKeyInfoDictionaryKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let infoDictionaryKey, !infoDictionaryKey.isEmpty {
            return infoDictionaryKey
        }

        return nil
    }
}
