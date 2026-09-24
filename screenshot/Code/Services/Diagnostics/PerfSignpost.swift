import Foundation
import OSLog

/// Instruments' Points of Interest track, plus — on a profiling run — a duration line per span on
/// `AppLogger.perf`, readable without attaching a tool:
///
///     log stream --predicate 'subsystem == "xyz.tleskiv.screenshot" && category == "Perf"'
///
/// Signposts stay on the device — nothing here reaches `AnalyticsService` or
/// `CrashReportingService` — but the payload rules are the same anyway: counts, enum-ish
/// constants and our own identifiers, never row labels or user text.
///
/// Compiled into Release, because that is the build worth measuring: `OSSignposter` is a no-op
/// until Instruments attaches, and `isEnabled` gates anything that costs more than the call itself.
/// A separate build configuration was tried and abandoned — Xcode only extracts SPM binary
/// artifacts (Sentry's XCFramework) for Debug and Release, so a third configuration and Debug
/// evict each other's copy in shared DerivedData.
nonisolated enum PerfSignpost {
    static let signposter = OSSignposter(
        subsystem: "xyz.tleskiv.screenshot",
        category: .pointsOfInterest
    )

    private static let profilingEnvironmentName = "SCREENSHOT_PERF"
    private static let minimumLoggedMillisecondsEnvironmentName = "SCREENSHOT_PERF_MIN_MS"

    /// Set by the `screenshot Profiling` scheme. Read once — `ProcessInfo.environment` rebuilds the
    /// whole dictionary on every access, and this is consulted on hot paths.
    ///
    /// It gates logging only. It must never gate a *capability* (no Pro unlock, no MCP auth
    /// bypass): this is a shipping build, so anything keyed on it is reachable by anyone who can
    /// set an environment variable.
    static let isProfilingRun: Bool = {
        ProcessInfo.processInfo.environment[profilingEnvironmentName] == "1"
    }()

    /// True when anything is listening: a profiling run, or an attached Instruments trace.
    static var isEnabled: Bool { isProfilingRun || signposter.isEnabled }

    /// Floor for the console line only; the Instruments interval is always emitted. Lets a noisy
    /// span be filtered out of a session without a rebuild.
    private static let minimumLoggedMilliseconds: Double = {
        Double(ProcessInfo.processInfo.environment[minimumLoggedMillisecondsEnvironmentName] ?? "") ?? 0
    }()

    /// An in-flight span. `nil` from `begin` means nothing is listening and `end` is a no-op, so a
    /// call site never needs to branch.
    struct Interval {
        fileprivate let state: OSSignpostIntervalState?
        fileprivate let detail: String
        fileprivate let start: ContinuousClock.Instant
    }

    /// Brackets a span of work. Pair with `end` via `defer` so an early return still closes it.
    /// `detail` is an autoclosure: it costs nothing in a normal run, where nothing is listening.
    static func begin(_ name: StaticString, _ detail: @autoclosure () -> String = "") -> Interval? {
        guard isEnabled else { return nil }
        let text = detail()
        return Interval(
            state: signposter.isEnabled ? signposter.beginInterval(name, "\(text)") : nil,
            detail: text,
            start: .now
        )
    }

    /// Pixel count is what predicts the cost of a rasterize, so it gets a named overload.
    static func begin(_ name: StaticString, pixels: Int) -> Interval? {
        begin(name, "pixels=\(pixels)")
    }

    static func end(_ name: StaticString, _ interval: Interval?) {
        guard let interval else { return }
        if let state = interval.state {
            signposter.endInterval(name, state)
        }
        guard isProfilingRun else { return }
        let elapsed = ContinuousClock.now - interval.start
        let milliseconds = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        guard milliseconds >= minimumLoggedMilliseconds else { return }
        let formatted = String(format: "%.1f", milliseconds)
        AppLogger.perf.log(
            "[\(name, privacy: .public)] \(interval.detail, privacy: .public) ▸ \(formatted, privacy: .public) ms"
        )
    }

    /// Sugar for the common shape. Async call sites use `begin`/`defer`/`end` directly — an async
    /// wrapper here would be a bare `nonisolated async func`, which inherits the caller's executor.
    static func measure<T>(
        _ name: StaticString,
        _ detail: @autoclosure () -> String = "",
        _ body: () throws -> T
    ) rethrows -> T {
        let interval = begin(name, detail())
        defer { end(name, interval) }
        return try body()
    }

    /// A point in time rather than a span — for something with no natural end (a cache hit, a retry).
    static func event(_ name: StaticString, _ detail: @autoclosure () -> String = "") {
        guard isEnabled else { return }
        let text = detail()
        if signposter.isEnabled {
            signposter.emitEvent(name, "\(text)")
        }
        if isProfilingRun {
            AppLogger.perf.log("[\(name, privacy: .public)] \(text, privacy: .public)")
        }
    }

    /// A body evaluation. Emitted as an event rather than an interval because SwiftUI gives us no
    /// hook for when a body *finishes* — the value is the count per frame, which is what tells you
    /// whether a hitch came from realizing rows. `row` is our own generated UUID, never the label.
    ///
    /// Signpost-only even on a profiling run: a console line per body evaluation would bury every
    /// other perf line in the stream.
    static func bodyEvaluated(_ name: StaticString, row: UUID, count: Int = 0) {
        guard signposter.isEnabled else { return }
        signposter.emitEvent(name, "row=\(row.uuidString.prefix(8)) n=\(count)")
    }
}
