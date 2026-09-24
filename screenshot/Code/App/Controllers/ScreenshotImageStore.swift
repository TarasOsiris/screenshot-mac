#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation

/// The editor's decoded screenshots, and the referenced resources the last decode pass could not
/// produce. Transient view state, not document state — an absent file is not an edit, and the
/// model deliberately keeps its reference so the bytes coming back later put the screenshot back.
///
/// `AppState` decides what to decode and when (it knows the active project, the progress pill and
/// the iCloud monitor); this owns the results and the verdict on what is missing.
@MainActor
@Observable
final class ScreenshotImageStore {
    /// Downsampled for the editor, keyed by resource file name. Export reloads full resolution.
    var images: [String: NSImage] = [:]
    /// Referenced resources the editor asked for and did not get.
    var missing: Set<String> = []
    /// The subset iCloud still owes us bytes for, which is a wait rather than a hole.
    var pending: Set<String> = []

    @ObservationIgnored var loadTask: Task<Void, Never>?
    /// A decode pass is running. iCloud delivers a large project's resources in bursts, and
    /// restarting the pass on each one would cancel the decode already in flight and reset the
    /// progress pill; `needsReload` is what turns those bursts into one follow-up pass.
    @ObservationIgnored var isLoading = false
    @ObservationIgnored var needsReload = false
    /// Reset per project so one absent file is one issue, not one per locale switch.
    @ObservationIgnored private var reported: Set<String> = []
    /// Holds the verdict on absent iCloud resources open until the file provider has had its
    /// chance. See `reportMissing`.
    @ObservationIgnored private var verdictTask: Task<Void, Never>?

    var hasUnresolved: Bool { !missing.isEmpty || !pending.isEmpty }

    /// The cancelled pass will never reach its finish, so it can't clear `isLoading` itself.
    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    /// Drops everything belonging to the outgoing project, including a verdict still pending.
    func reset() {
        cancelLoad()
        needsReload = false
        images = [:]
        missing = []
        pending = []
        reported = []
        verdictTask?.cancel()
        verdictTask = nil
    }

    /// Evicts what the editor no longer references (e.g. after a locale switch) and returns the
    /// names that still need decoding, in the editor's order so the project fills in from the top.
    func retain(only needed: [String]) -> [String] {
        let keep = Set(needed)
        // One write each, and none when nothing changed: every write invalidates the canvases.
        if images.keys.contains(where: { !keep.contains($0) }) {
            images = images.filter { keep.contains($0.key) }
        }
        if !missing.isSubset(of: keep) { missing.formIntersection(keep) }
        if !pending.isSubset(of: keep) { pending.formIntersection(keep) }
        return needed.filter { images[$0] == nil }
    }

    func publish(_ decoded: [String: NSImage]) {
        images.merge(decoded) { _, new in new }
        // A resource that arrived is neither missing nor pending any more, and this is the only
        // place that knows it — a retry re-reads the same names, so nothing else clears them.
        missing.subtract(decoded.keys)
        pending.subtract(decoded.keys)
    }

    func record(_ unloadable: UnloadableResources) {
        missing.formUnion(unloadable.missing)
        pending.formUnion(unloadable.pending)
        reportMissing(unloadable.missing, pending: unloadable.pending.count)
    }

    /// How long an iCloud project gets to finish arriving before an absent resource counts as a
    /// hole. Long enough to cover the placeholder gap below, short enough that the report still
    /// lands in the session it belongs to.
    private static let missingResourceVerdictDelay = Duration.seconds(60)

    /// On iCloud the first pass is the wrong moment to judge. A peer's `project.json` is one small
    /// file and lands before the file provider has placeholders for the resources it names, so
    /// every one of them stats as absent — which is why the reports that came back read
    /// `loaded: 0, missing: 38, pending: 0`, a project that was merely still arriving. Judging
    /// after a grace period instead reads the live set, which the retry passes
    /// (`AppState.reloadUnresolvedScreenshotImages`) have been subtracting from meanwhile.
    ///
    /// Local storage judges immediately: there is nothing on the way, so absent is absent.
    ///
    /// A switch or a quit inside the window cancels the verdict rather than forcing it, and that is
    /// the trade: reporting on teardown would report the project the user merely glanced at
    /// mid-sync, which is the false positive this exists to remove. Nothing is lost permanently —
    /// the dedupe set is per project, so the next open that lasts a minute asks again.
    private func reportMissing(_ missing: Set<String>, pending: Int) {
        guard PersistenceService.isUsingICloud else {
            emitMissingResourceReport(missing, pending: pending)
            return
        }
        // The first failing pass starts the clock and later ones join it. Restarting it per pass
        // would let a project that syncs in bursts postpone the verdict indefinitely.
        guard verdictTask == nil else { return }
        verdictTask = Task { [weak self] in
            try? await Task.sleep(for: Self.missingResourceVerdictDelay)
            guard !Task.isCancelled, let self else { return }
            verdictTask = nil
            emitMissingResourceReport(self.missing, pending: self.pending.count)
        }
    }

    /// Counts only, and once per name per project — the file names would say what the user is
    /// building, and a locale switch re-walks the same resources.
    ///
    /// `.warning`, not the default error level: a resource can also be absent because iCloud
    /// hasn't caught up or the user removed the file, and neither is our bug. It stays a report
    /// rather than a breadcrumb because a project whose resources have vanished is the most
    /// damaging failure this app has had, and the last one went unnoticed for two days.
    private func emitMissingResourceReport(_ missing: Set<String>, pending: Int) {
        let unreported = missing.subtracting(reported)
        guard !unreported.isEmpty else { return }
        reported.formUnion(unreported)
        CrashReportingService.report(.referencedResourceMissing, extra: [
            "missing": unreported.count,
            "pending": pending,
            "loaded": images.count,
            "icloud": PersistenceService.isUsingICloud,
        ], level: .warning)
    }
}

/// What the decode loop couldn't produce, split by whose fault it is. `notDownloaded` is a wait —
/// the file provider owes us the bytes — so it asks for them rather than reporting a hole.
/// `nonisolated` because the decode loop that fills it is detached.
nonisolated struct UnloadableResources {
    var missing: Set<String> = []
    var pending: Set<String> = []

    var isEmpty: Bool { missing.isEmpty && pending.isEmpty }

    /// `availability` stats a ubiquitous path, which can block, so this must stay off the main actor.
    mutating func record(_ fileName: String, at url: URL) {
        switch PersistenceService.availability(of: url) {
        case .notDownloaded: pending.insert(fileName)
        case .present, .absent: missing.insert(fileName)
        }
    }
}
