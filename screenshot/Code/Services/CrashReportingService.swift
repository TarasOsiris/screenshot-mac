import Foundation
import OSLog
import Sentry

nonisolated enum CrashReportingService {
    private static let dsn = "https://0777a0589cda6e0a1342d8a5df6012af@o1145835.ingest.us.sentry.io/4511911008927744"

    /// Cached once: `isRunningUnderXCTest` rebuilds the process environment on every read, and
    /// breadcrumbs sit on the edit path. Its inputs are fixed for the process lifetime.
    static let isReportingEnabled = !PersistenceService.isRunningUnderXCTest

    /// Whether the SDK actually started. `screenshotTests` is a hosted target, so the app launches
    /// and calls `start()` for real during a test run — this is what proves nothing can be
    /// transmitted from one (no client, no transport, regardless of any call site's own guard).
    static var isActive: Bool { SentrySDK.isEnabled }

    /// Breadcrumb grouping in the Sentry trail. Call sites go through `Category`/`Level`/`Failure`
    /// rather than Sentry's own types so `import Sentry` stays confined to this file.
    enum Category: String {
        case app, project, edit, persistence, sync, export, upload, store, mcp, media
    }

    enum Level: String {
        case info, warning, error
    }

    /// Failures we consider our own bug. The raw value is both the issue title and the
    /// fingerprint, so grouping follows the cause rather than a localized `Error` string
    /// (which would fragment one issue across 30 languages).
    enum Failure: String, CaseIterable {
        case projectDecodeFailed
        case projectReadFailed
        case projectLoadFellBackToEmpty
        case projectSaveFailed
        case projectIndexSaveFailed
        case projectDirectoryCopyFailed
        case directoryCreateFailed
        case iCloudCoordinatedReadFailed
        case imageResourceCopyFailed
        case customFontCopyFailed
        case renderProducedBlankImage
        case imageEncodeFailed
        case exportFolderBookmarkFailed
        case richTextEncodeFailed
        case richTextDecodeFailed
        case bundledTemplateLoadFailed
        case storeConfigurationInvalid
        case appStoreOrphanCleanupFailed
        case googlePlayEditAbandonFailed
        case undoScopeViolation
        case mcpToolFailed
    }

    // MARK: - Lifecycle

    static func start() {
        guard isReportingEnabled else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.dist = Bundle.main.buildNumber
            options.sendDefaultPii = false

            options.enableAppHangTracking = true
            // Default is 2s, which large synchronous ImageRenderer exports routinely exceed.
            options.appHangTimeoutInterval = 3

            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0

            // Off by default in SDK v9. Stitches the frames across `await` hops back into one
            // stack — without it async crash/hang stacks stop at the suspension point, which is
            // most of this app (saveQueue, TaskGroup exports, upload services).
            options.swiftAsyncStacktraces = true

            // Off by default in SDK v9. MetricKit delivers hang/crash/disk-write diagnostics the
            // in-process watchdog can't see (notably hangs during termination).
            options.enableMetricKit = true

            // One breadcrumb per edit action fills the default 100 within a minute of editing.
            options.maxBreadcrumbs = 200

            // Apple's and Google's 5xx are their outage, not our bug — the upload sheets already
            // surface them. Left on, every store hiccup would open an issue.
            options.enableCaptureFailedRequests = false

            options.beforeSend = { event in
                guard isReportingEnabled else { return nil }
                return scrubbed(event)
            }

            // Deliberately left off, and must stay off: the privacy policy promises reports carry
            // no project content and no stream of usage events.
            // options.enableLogs / options.attachScreenshot / options.attachViewHierarchy

            #if os(macOS)
            // AppKit swallows uncaught NSExceptions on the main run loop, so Sentry never sees them
            // without this. Mutually exclusive with SentryCrashExceptionApplication as principal class.
            options.enableUncaughtNSExceptionReporting = true
            #endif

            #if DEBUG
            options.environment = "debug"
            options.debug = true
            #else
            options.environment = "production"
            #endif
        }

        if SentrySDK.crashedLastRun {
            setTag("true", for: "crashed_last_run")
            breadcrumb(.app, "Previous run crashed", level: .warning)
        }
    }

    // MARK: - Scope

    /// No-ops on a missing id rather than clearing: RevenueCat stays unconfigured in the
    /// force-pro-unlock path and when the API key is absent, neither of which should drop a
    /// user already attached to the scope.
    static func setUser(id: String?) {
        guard isReportingEnabled, let id, !id.isEmpty else { return }
        let user = User()
        user.userId = id
        SentrySDK.setUser(user)
    }

    static func setTag(_ value: String?, for key: String) {
        guard isReportingEnabled else { return }
        SentrySDK.configureScope { scope in
            if let value {
                scope.setTag(value: value, key: key)
            } else {
                scope.removeTag(key: key)
            }
        }
    }

    /// Shape of the open document, so an export/render failure says how much it was chewing on.
    /// Counts and enum names only — never project, row, locale, or text content.
    static func setDocumentContext(_ values: [String: Any]) {
        guard isReportingEnabled else { return }
        SentrySDK.configureScope { scope in
            scope.setContext(value: values, key: "document")
        }
    }

    // MARK: - Breadcrumbs

    static func breadcrumb(
        _ category: Category,
        _ message: String,
        data: [String: Any]? = nil,
        level: Level = .info
    ) {
        guard isReportingEnabled else { return }
        guard shouldEmitBreadcrumb(category: category, message: message) else { return }

        let crumb = Breadcrumb(level: level.sentryLevel, category: category.rawValue)
        crumb.message = message
        data?.forEach { crumb.setData(value: $0.value, key: $0.key) }
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Capture

    /// Reports a failure we're responsible for. Logs it too, so the console trail and Sentry
    /// can't drift apart. Expected user/network failures must not come through here.
    static func report(
        _ failure: Failure,
        error: Error? = nil,
        extra: [String: Any] = [:],
        level: Level = .error
    ) {
        var payload = extra
        if let error {
            let nsError = error as NSError
            payload["error_type"] = String(describing: type(of: error))
            payload["error_domain"] = nsError.domain
            payload["error_code"] = nsError.code
            payload["error_detail"] = scrubbingPaths(String(describing: error).prefix(1_000).description)
        }

        log(failure, payload: payload, level: level)
        guard isReportingEnabled else { return }

        SentrySDK.capture(message: failure.rawValue) { scope in
            scope.setLevel(level.sentryLevel)
            scope.setFingerprint([failure.rawValue])
            scope.setTag(value: failure.rawValue, key: "failure")
            payload.forEach { scope.setExtra(value: $0.value, key: $0.key) }
        }
    }

    // MARK: - Scrubbing

    private static let homePrefix = "/Users/"
    private static let pathTerminators: Set<Character> = ["/", "\\", " ", "\t", "\n", "\"", "'", ",", ")", "]", "}"]

    /// `/Users/<name>/…` → `/Users/~/…`. `sendDefaultPii = false` already drops IP and device
    /// name, but a file path in an error message still leaks the OS user name.
    static func scrubbingPaths(_ text: String) -> String {
        guard text.contains(homePrefix) else { return text }

        var result = ""
        var remainder = Substring(text)
        while let marker = remainder.range(of: homePrefix) {
            result += remainder[..<marker.upperBound]
            result += "~"
            let rest = remainder[marker.upperBound...]
            remainder = rest.drop { !pathTerminators.contains($0) }
        }
        return result + remainder
    }

    private static func scrubbed(_ event: Event) -> Event {
        if let formatted = event.message?.formatted {
            event.message = SentryMessage(formatted: scrubbingPaths(formatted))
        }
        event.exceptions?.forEach { exception in
            exception.value = exception.value.map(scrubbingPaths)
        }
        event.extra = event.extra?.mapValues { value in
            (value as? String).map { scrubbingPaths($0) as Any } ?? value
        }
        event.breadcrumbs?.forEach { crumb in
            crumb.message = crumb.message.map(scrubbingPaths)
        }
        return event
    }

    // MARK: - Breadcrumb de-duplication

    private static let breadcrumbLock = NSLock()
    private nonisolated(unsafe) static var lastBreadcrumbKey: String?

    /// A run of identical crumbs (`Move Shape` on every drag commit) would evict the rest of the
    /// trail, so only the first of a run is kept.
    static func shouldEmitBreadcrumb(category: Category, message: String) -> Bool {
        let key = "\(category.rawValue)|\(message)"
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        guard lastBreadcrumbKey != key else { return false }
        lastBreadcrumbKey = key
        return true
    }

    static func resetBreadcrumbDeduplication() {
        breadcrumbLock.lock()
        lastBreadcrumbKey = nil
        breadcrumbLock.unlock()
    }

    // MARK: - Logging

    private static func log(_ failure: Failure, payload: [String: Any], level: Level) {
        let detail = payload.isEmpty ? "" : " \(payload.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))"
        let line = "\(failure.rawValue)\(detail)"
        switch level {
        case .error: logger(for: failure).error("\(line, privacy: .public)")
        case .warning: logger(for: failure).warning("\(line, privacy: .public)")
        case .info: logger(for: failure).log("\(line, privacy: .public)")
        }
    }

    private static func logger(for failure: Failure) -> Logger {
        switch failure {
        case .projectDecodeFailed, .projectReadFailed, .projectLoadFellBackToEmpty,
             .projectSaveFailed, .projectIndexSaveFailed, .projectDirectoryCopyFailed,
             .directoryCreateFailed, .imageResourceCopyFailed, .customFontCopyFailed,
             .bundledTemplateLoadFailed, .undoScopeViolation:
            AppLogger.persistence
        case .iCloudCoordinatedReadFailed:
            AppLogger.sync
        case .renderProducedBlankImage, .imageEncodeFailed, .exportFolderBookmarkFailed:
            AppLogger.export
        case .richTextEncodeFailed, .richTextDecodeFailed:
            AppLogger.media
        case .storeConfigurationInvalid:
            AppLogger.store
        case .appStoreOrphanCleanupFailed, .googlePlayEditAbandonFailed:
            AppLogger.upload
        case .mcpToolFailed:
            AppLogger.mcp
        }
    }
}

private extension CrashReportingService.Level {
    nonisolated var sentryLevel: SentryLevel {
        switch self {
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
