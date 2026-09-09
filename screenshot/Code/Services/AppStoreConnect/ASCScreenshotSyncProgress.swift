import Foundation

/// Progress from `buildPlan`, typed.
///
/// The previous channel was a bare label string. It carried user-written row and locale names and
/// no counts at all, so anything wanting to report "74 of 180" had to parse prose — fragile, and
/// the wrong shape for a payload that has to distinguish what may be transmitted from what may not.
nonisolated struct ASCSyncBuildProgress: Sendable {
    enum Stage: String, Sendable {
        case rendering
        case comparing
    }

    let stage: Stage
    let completedRenders: Int
    let totalRenders: Int
    /// Row · locale, user-written. Fine in the UI and in a tool result; never in a breadcrumb.
    let label: String
}

/// Per-set transitions from `apply`. Deliberately separate from `UploadProgress`, which carries the
/// step numbers and the GUI's label but says nothing about which set reached what state.
nonisolated enum ASCSyncApplySetEvent: Sendable {
    case started(setId: String)
    case finished(ASCScreenshotSetSyncResult)
    /// Something was written to the live listing. Reported as soon as it is true, because on a
    /// failure it is the difference between "nothing was touched" and "half-updated".
    case didMutate
}
