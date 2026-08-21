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
        case iCloudMergeSourceUnreadable
        case iCloudConflictDiscardedVersions
        case imageResourceCopyFailed
        case customFontCopyFailed
        case renderProducedBlankImage
        case imageEncodeFailed
        case exportFolderBookmarkFailed
        case richTextEncodeFailed
        case richTextDecodeFailed
        case bundledTemplateLoadFailed
        case storeConfigurationInvalid
        case analyticsConfigurationInvalid
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

            options.beforeBreadcrumb = { crumb in filteredBreadcrumb(crumb) }

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

        // Before anything else can capture: an event without this is an event nobody can trace
        // back to the person who emailed about it.
        setUser(id: DiagnosticsIdentity.installId)
        setTag(DiagnosticsIdentity.firstVersion, for: "first_version")

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

    // MARK: - App hangs

    /// Runs `body` with app-hang reporting suppressed, for the one case the watchdog cannot tell
    /// from a freeze: a modal AppKit panel. `NSSavePanel`/`NSOpenPanel.runModal` spins its own run
    /// loop until the user picks a file, so any browse longer than `appHangTimeoutInterval` is
    /// reported as our hang (SCREENSHOT-BRO-Q). Wrap every `runModal` call site, not the async
    /// work around it — real hangs on either side must still be reported.
    @MainActor
    static func withAppHangTrackingPaused<T>(_ body: () throws -> T) rethrows -> T {
        guard isReportingEnabled else { return try body() }
        // The SDK's own switch is a plain flag, so nesting two panels would resume too early.
        appHangPauseDepth += 1
        if appHangPauseDepth == 1 { SentrySDK.pauseAppHangTracking() }
        defer {
            appHangPauseDepth -= 1
            if appHangPauseDepth == 0 { SentrySDK.resumeAppHangTracking() }
        }
        return try body()
    }

    @MainActor private static var appHangPauseDepth = 0

    // MARK: - Breadcrumbs

    static func breadcrumb(
        _ category: Category,
        _ message: String,
        data: [String: Any]? = nil,
        level: Level = .info
    ) {
        guard isReportingEnabled else { return }

        // `addBreadcrumb` takes the SDK's own locks — never call it while holding ours, which
        // `recordBreadcrumbRun` has already released by the time it returns.
        switch recordBreadcrumbRun(category: category, message: message) {
        case .coalesce:
            return
        case .checkpoint(let count):
            addRunSummary(category: category, message: message, count: count, level: level)
            return
        case .summarizeThenEmit(let previousCategory, let previousMessage, let count):
            addRunSummary(category: previousCategory, message: previousMessage, count: count, level: .info)
        case .emit:
            break
        }

        let crumb = Breadcrumb(level: level.sentryLevel, category: category.rawValue)
        crumb.message = message
        data?.forEach { crumb.setData(value: $0.value, key: $0.key) }
        SentrySDK.addBreadcrumb(crumb)
    }

    private static func addRunSummary(category: Category, message: String, count: Int, level: Level) {
        let crumb = Breadcrumb(level: level.sentryLevel, category: category.rawValue)
        crumb.message = "\(message) ×\(count)"
        crumb.setData(value: count, key: "count")
        SentrySDK.addBreadcrumb(crumb)
    }

    // MARK: - Capture

    /// Reports a failure we're responsible for. Logs it too, so the console trail and Sentry
    /// can't drift apart. Expected user/network failures must not come through here.
    /// Failures a full disk explains. Attached in `report` rather than at each call site — reports
    /// are rare, so one `stat` is free, and no caller has to remember.
    private static let storageBoundFailures: Set<Failure> = [
        .projectSaveFailed, .projectIndexSaveFailed, .projectDirectoryCopyFailed,
        .directoryCreateFailed, .imageResourceCopyFailed, .customFontCopyFailed,
        .imageEncodeFailed, .iCloudCoordinatedReadFailed, .iCloudMergeSourceUnreadable,
    ]

    /// `volumeAvailableCapacityForImportantUsage` counts purgeable space, so it is the number that
    /// explains a save failing on a Mac whose Finder claims 40 GB free.
    private static var freeDiskMB: Int? {
        let values = try? PersistenceService.rootURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        )
        guard let bytes = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return Int(bytes / 1_000_000)
    }

    static func report(
        _ failure: Failure,
        error: Error? = nil,
        extra: [String: Any] = [:],
        level: Level = .error
    ) {
        var payload = extra
        if storageBoundFailures.contains(failure), let freeDiskMB {
            payload["free_disk_mb"] = freeDiskMB
        }
        if let error {
            let nsError = error as NSError
            payload["error_type"] = String(describing: type(of: error))
            payload["error_domain"] = nsError.domain
            payload["error_code"] = nsError.code
            payload["error_detail"] = scrubbingPaths(String(describing: error).prefix(1_000).description)
        }

        log(failure, payload: payload, level: level)
        guard isReportingEnabled else { return }

        // Close the open run first, or the trail attached to this event ends mid-run with a
        // stale count.
        if let run = flushBreadcrumbRun() {
            addRunSummary(category: run.category, message: run.message, count: run.count, level: .info)
        }

        SentrySDK.capture(message: failure.rawValue) { scope in
            scope.setLevel(level.sentryLevel)
            scope.setFingerprint([failure.rawValue])
            scope.setTag(value: failure.rawValue, key: "failure")
            payload.forEach { scope.setExtra(value: $0.value, key: $0.key) }
        }
    }

    // MARK: - Automatic breadcrumb filtering

    /// The SDK's UIKit swizzling (on by default, iPad only) emits a `touch` crumb per control
    /// interaction carrying the tapped button's *title* and accessibility identifier, plus a
    /// `ui.lifecycle` crumb per view controller — the stream of usage events, and the user-facing
    /// text, that the privacy policy rules out. Network crumbs earn their keep for upload bugs,
    /// minus the query and fragment, which are where the store APIs put ids and tokens.
    private static func filteredBreadcrumb(_ crumb: Breadcrumb) -> Breadcrumb? {
        switch crumb.category {
        case "touch", "ui.lifecycle":
            return nil
        case "http":
            // `setData(value: nil, key:)` removes the key; the `data` setter is deprecated.
            crumb.setData(value: nil, key: "http.query")
            crumb.setData(value: nil, key: "http.fragment")
            return crumb
        default:
            return crumb
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

    // MARK: - Breadcrumb run coalescing

    /// What to do with a crumb, given what preceded it. Pure, so the policy is testable without
    /// touching the SDK.
    enum RunDecision: Equatable {
        /// First of a run — emit as-is.
        case emit
        /// Still inside a run; nothing to emit.
        case coalesce
        /// Still inside a long run, at a checkpoint — emit a progress summary.
        case checkpoint(count: Int)
        /// The run ended. Emit a summary for the finished run, then the new crumb.
        case summarizeThenEmit(category: Category, message: String, count: Int)
    }

    /// Emitted at these run lengths so a crash *during* a long run still shows roughly how long it
    /// had been going — the end-of-run summary never gets written in that case.
    private static let runCheckpoints: Set<Int> = [10, 100, 1_000]

    private static let breadcrumbLock = NSLock()
    private nonisolated(unsafe) static var runKey: String?
    private nonisolated(unsafe) static var runCategory: Category?
    private nonisolated(unsafe) static var runMessage: String?
    private nonisolated(unsafe) static var runCount = 0

    /// A run of identical crumbs (`Move Shape` on every drag commit) would evict the rest of the
    /// trail, so only the first of a run is emitted live — but the count is carried and reported
    /// when the run ends, which is what tells forty drags apart from one.
    static func recordBreadcrumbRun(category: Category, message: String) -> RunDecision {
        let key = "\(category.rawValue)|\(message)"
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }

        if runKey == key {
            runCount += 1
            return runCheckpoints.contains(runCount) ? .checkpoint(count: runCount) : .coalesce
        }

        let finished = (runCategory, runMessage, runCount)
        runKey = key
        runCategory = category
        runMessage = message
        runCount = 1

        if let category = finished.0, let previous = finished.1, finished.2 > 1 {
            return .summarizeThenEmit(category: category, message: previous, count: finished.2)
        }
        return .emit
    }

    /// Closes the open run so a report's trail ends with an accurate count. Returns the summary to
    /// emit, if the run was long enough to have one.
    static func flushBreadcrumbRun() -> (category: Category, message: String, count: Int)? {
        breadcrumbLock.lock()
        defer { breadcrumbLock.unlock() }
        let finished = (runCategory, runMessage, runCount)
        runKey = nil
        runCategory = nil
        runMessage = nil
        runCount = 0
        guard let category = finished.0, let message = finished.1, finished.2 > 1 else { return nil }
        return (category, message, finished.2)
    }

    static func resetBreadcrumbDeduplication() {
        breadcrumbLock.lock()
        runKey = nil
        runCategory = nil
        runMessage = nil
        runCount = 0
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
        case .iCloudCoordinatedReadFailed, .iCloudMergeSourceUnreadable, .iCloudConflictDiscardedVersions:
            AppLogger.sync
        case .renderProducedBlankImage, .imageEncodeFailed, .exportFolderBookmarkFailed:
            AppLogger.export
        case .richTextEncodeFailed, .richTextDecodeFailed:
            AppLogger.media
        case .storeConfigurationInvalid:
            AppLogger.store
        case .analyticsConfigurationInvalid:
            AppLogger.analytics
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
