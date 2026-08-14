import Foundation
import Sentry

nonisolated enum CrashReportingService {
    private static let dsn = "https://0777a0589cda6e0a1342d8a5df6012af@o1145835.ingest.us.sentry.io/4511911008927744"

    static func start() {
        guard !PersistenceService.isRunningUnderXCTest else { return }

        SentrySDK.start { options in
            options.dsn = dsn
            options.dist = Bundle.main.buildNumber
            options.sendDefaultPii = false

            options.enableAppHangTracking = true
            // Default is 2s, which large synchronous ImageRenderer exports routinely exceed.
            options.appHangTimeoutInterval = 3

            options.enableAutoPerformanceTracing = false
            options.tracesSampleRate = 0

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
    }

    /// No-ops on a missing id rather than clearing: RevenueCat stays unconfigured in the
    /// force-pro-unlock path and when the API key is absent, neither of which should drop a
    /// user already attached to the scope.
    static func setUser(id: String?) {
        guard let id, !id.isEmpty else { return }
        let user = User()
        user.userId = id
        SentrySDK.setUser(user)
    }

    #if DEBUG
    static func captureTestEvent() {
        SentrySDK.capture(message: "Test event from Screenshot Bro")
    }
    #endif
}
