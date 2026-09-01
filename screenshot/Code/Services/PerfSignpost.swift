import Foundation
import OSLog

/// Instruments' Points of Interest track for the live editor.
///
/// Signposts stay on the device — nothing here reaches `AnalyticsService` or
/// `CrashReportingService` — but the payload rules are the same anyway: counts, enum-ish
/// constants and our own identifiers, never row labels or user text.
///
/// Compiled into Release: `OSSignposter` is a no-op until Instruments attaches, and
/// `isEnabled` gates anything that costs more than the call itself.
nonisolated enum PerfSignpost {
    static let signposter = OSSignposter(
        subsystem: "xyz.tleskiv.screenshot",
        category: .pointsOfInterest
    )

    static var isEnabled: Bool { signposter.isEnabled }

    /// A body evaluation. Emitted as an event rather than an interval because SwiftUI gives us no
    /// hook for when a body *finishes* — the value is the count per frame, which is what tells you
    /// whether a hitch came from realizing rows. `row` is our own generated UUID, never the label.
    static func bodyEvaluated(_ name: StaticString, row: UUID, count: Int = 0) {
        guard isEnabled else { return }
        signposter.emitEvent(name, "row=\(row.uuidString.prefix(8)) n=\(count)")
    }

    /// Brackets a synchronous rasterize. `pixels` is the only payload — it is what predicts the
    /// cost. Paired with `end` via `defer`, so an early return still closes the interval; `nil`
    /// state means no tool is attached and `end` is a no-op.
    static func begin(_ name: StaticString, pixels: Int) -> OSSignpostIntervalState? {
        guard isEnabled else { return nil }
        return signposter.beginInterval(name, "pixels=\(pixels)")
    }

    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        signposter.endInterval(name, state)
    }
}
