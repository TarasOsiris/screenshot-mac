import Foundation

/// How `buildPlan` decides what to upload. Orthogonal to `ASCFlowMode`, which is the job type.
///
/// `replaceAll` changes the *matching* only, never the fetch: `apply` revalidates each set by
/// re-reading the remote and comparing `remoteFingerprint`, which includes each asset's checksum
/// and index — so a build that skipped the detail GETs or the order call would disagree with its
/// own revalidation and fail as `staleRemote` every time. What makes the direct path fast is
/// `needsPreviews`, not the strategy.
nonisolated enum ASCSyncStrategy: String, Sendable {
    /// Match local to remote by checksum; upload what differs, preserve what doesn't.
    case reconcile
    /// Treat every remote asset as a removal and every local one as an upload.
    case replaceAll
}

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
