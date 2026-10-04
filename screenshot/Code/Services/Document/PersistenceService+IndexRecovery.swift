import Foundation

nonisolated extension PersistenceService {
    static func loadIndex() -> ProjectIndex? {
        guard case .loaded(let index) = loadIndex(at: rootURL) else { return nil }
        return index
    }

    static func saveIndex(_ index: ProjectIndex) throws {
        try saveIndex(index, at: rootURL)
    }

    /// `root` is where the index was read from, and the only root a `wasRecovered` write-back may
    /// go to: resolving it again at the write moves this function's race to the caller.
    struct LoadedIndex {
        let index: ProjectIndex
        let wasRecovered: Bool
        let root: URL
    }

    /// The index is the one file whose loss makes every project invisible even though each
    /// project's data is still sitting in `projects/<uuid>/` — without this, a missing
    /// `projects.json` presents as "all your projects are gone" and the next save writes an empty
    /// index over the top. Returns nil (callers keep their current list) when there is nothing to
    /// recover.
    static func loadIndexOrRecover() -> LoadedIndex? {
        loadIndexOrRecover(isUsingICloud: isUsingICloud)
    }

    /// `isUsingICloud` is injected so both branches are testable — the real flag needs a resolved
    /// ubiquity container, which a test process never has.
    static func loadIndexOrRecover(isUsingICloud: Bool) -> LoadedIndex? {
        // One root for the whole operation, so the read and the rebuild guard below can't
        // disagree about the storage mode.
        let root = rootURL(isUsingICloud: isUsingICloud)
        let result = loadIndex(at: root)
        switch result {
        case .loaded(let index):
            return LoadedIndex(index: index, wasRecovered: false, root: root)
        case .absent, .unreadable:
            // Local only, and the reason is the same for both: an iCloud index may simply not be
            // there *yet* — the container can still be materializing, the coordinated read can
            // fail, the device can be offline — and a rebuild would push an index missing every
            // project this device has never opened out to all the others.
            //
            // For `.absent` the damage is worse still. A rebuild has no names to work from: they
            // live in the index, and `ProjectData.name` only mirrors them for projects saved since
            // that mirror shipped. So a rebuilt index renames every project to "Recovered Project"
            // — and then syncs that over the real names everywhere. That happened; it cost 51
            // names. Coming back with nothing costs a launch, because `ICloudMonitor` re-runs this
            // as soon as the real index lands.
            guard !isUsingICloud, let rebuilt = rebuildIndexFromProjectDirs(at: root) else { return nil }
            let reason: String
            if case .unreadable = result {
                // Keeps the bytes we couldn't parse, so a rebuild never destroys the only copy.
                preserveUnreadableIndex(at: root)
                reason = "unreadable"
            } else {
                reason = "absent"
            }
            reportRebuild(rebuilt, reason: reason)
            return LoadedIndex(index: rebuilt, wasRecovered: true, root: root)
        }
    }

    /// Best-effort scan of `projects/` for anything that still decodes. Junk entries are skipped
    /// silently — the point is to salvage what is there, not to audit the folder.
    static func rebuildIndexFromProjectDirs(at root: URL) -> ProjectIndex? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir(at: root),
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var recovered: [Project] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let data = recoverableProjectData(id, at: root) else { continue }
            var project = Project(id: id, name: data.name ?? String(localized: "Recovered Project"))
            project.modifiedAt = data.modifiedAt
            recovered.append(project)
        }

        guard !recovered.isEmpty else { return nil }
        recovered.sort { $0.modifiedAt > $1.modifiedAt }
        return ProjectIndex(projects: recovered, activeProjectId: recovered.first?.id)
    }

    /// Quiet counterpart of `loadProject` for the recovery scan: no decode report, and no catalog
    /// merge — the rebuild only needs `name` and `modifiedAt`. Bypasses `readData` for the reason
    /// `loadIndex(at:)` does; the call site's guard already makes `root` local.
    private static func recoverableProjectData(_ id: UUID, at root: URL) -> ProjectData? {
        guard let data = try? Data(contentsOf: projectDataURL(id, at: root)) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    /// Keeps the bytes we couldn't parse so a rebuild never destroys the only copy of the list.
    private static func preserveUnreadableIndex(at root: URL) {
        let url = indexURL(at: root)
        let backup = url.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: url, to: backup)
    }

    private static func reportRebuild(_ index: ProjectIndex, reason: String) {
        CrashReportingService.breadcrumb(
            .persistence,
            "Rebuilt project index",
            data: ["projects": index.projects.count, "reason": reason],
            level: .warning
        )
        CrashReportingService.report(
            .projectIndexRebuilt,
            extra: ["projects": index.projects.count, "reason": reason],
            level: .warning
        )
    }

    // MARK: - Explicit-root index I/O
    // Coordination follows the root these take, not the global `isUsingICloud`, which still
    // describes the old mode while an enable/disable migration is in flight.

    /// Distinguishing these two is what stops a migration from merging against an empty set:
    /// an index that is merely unreadable must not look like a first run.
    enum IndexLoadResult {
        case absent
        case loaded(ProjectIndex)
        case unreadable
    }

    /// The migration counterpart of `loadIndex()`. It can't just delegate, because `readData`
    /// picks coordination from the global `isUsingICloud`, which still describes the *old* mode
    /// while a switch is in flight — so the root being read decides instead.
    static func loadIndex(at root: URL) -> IndexLoadResult {
        let url = indexURL(at: root)
        let data: Data?

        if isICloudRoot(root) {
            data = ICloudSyncService.shared.coordinatedRead(from: url)
        } else {
            do {
                data = try Data(contentsOf: url)
            } catch {
                guard indexExists(at: url) else { return .absent }
                CrashReportingService.report(.projectReadFailed, error: error, extra: ["file": url.lastPathComponent])
                return .unreadable
            }
        }

        guard let data else {
            return indexExists(at: url) ? .unreadable : .absent
        }

        guard let index = decodeReportingFailure(ProjectIndex.self, from: data, file: url) else {
            return .unreadable
        }
        return .loaded(index)
    }

    /// The write counterpart of `loadIndex(at:)`: coordination follows the root being written.
    static func saveIndex(_ index: ProjectIndex, at root: URL) throws {
        // A root removed mid-session (cleaner, container reset) otherwise fails every write with ENOENT.
        ensureDirectories(at: root)
        let url = indexURL(at: root)
        let data = try encoder.encode(index)
        try writeData(data, to: url, inRoot: root)
    }

    static func isICloudRoot(_ root: URL) -> Bool {
        guard let dataURL = ICloudSyncService.shared.iCloudDataURL else { return false }
        return root.standardizedFileURL == dataURL.standardizedFileURL
    }

    /// Reading a not-yet-materialized index as "absent" is exactly what let a merge run against
    /// zero projects, so its placeholder counts as present.
    private static func indexExists(at url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.path)
            || fm.fileExists(atPath: ubiquitousPlaceholderURL(for: url).path)
    }
}
