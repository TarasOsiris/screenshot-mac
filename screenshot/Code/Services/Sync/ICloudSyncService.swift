import Foundation

extension Notification.Name {
    static let iCloudSyncDidEnable = Notification.Name("iCloudSyncDidEnable")
    static let iCloudSyncDidDisable = Notification.Name("iCloudSyncDidDisable")
}

nonisolated final class ICloudSyncService: @unchecked Sendable {
    static let shared = ICloudSyncService()

    private let containerID = "iCloud.xyz.tleskiv.screenshot"
    private static let dataSubpath = "Documents/screenshot"

    /// Marker file in the LOCAL app support directory (never synced via iCloud).
    /// Using a file instead of UserDefaults because sandboxed apps with iCloud
    /// entitlements can have their UserDefaults synced across Macs.
    private static var enabledMarkerURL: URL {
        PersistenceService.localRootURL.appendingPathComponent(".icloud-sync-enabled")
    }

    private let containerLock = NSLock()
    private var _iCloudContainerURL: URL?

    var iCloudContainerURL: URL? {
        containerLock.lock()
        defer { containerLock.unlock() }
        return _iCloudContainerURL
    }

    var isEnabled: Bool { FileManager.default.fileExists(atPath: Self.enabledMarkerURL.path) }

    var isAvailable: Bool { FileManager.default.ubiquityIdentityToken != nil }

    var isUsingICloud: Bool { isEnabled && iCloudContainerURL != nil }

    /// The iCloud data directory URL, or nil if iCloud container is not resolved.
    var iCloudDataURL: URL? {
        iCloudContainerURL?.appendingPathComponent(Self.dataSubpath, isDirectory: true)
    }

    private init() {}

    // MARK: - Container Resolution

    /// Resolve the iCloud container URL. The blocking lookup runs off the main thread.
    func resolveContainer() async -> URL? {
        let url = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: self.containerID)
        }.value
        containerLock.withLock {
            _iCloudContainerURL = url
        }
        return url
    }

    // MARK: - Enable / Disable

    /// Enable iCloud sync: merges local projects into iCloud, then switches to iCloud.
    /// `@concurrent` is load-bearing — `mergeProjects` is synchronous and its coordinated iCloud
    /// reads block; without it this inherits the calling view's main actor. See CLAUDE.md.
    @concurrent func enable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        if iCloudContainerURL == nil {
            _ = await resolveContainer()
        }
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        CrashReportingService.breadcrumb(.sync, "Enabling iCloud sync")
        let localRoot = PersistenceService.localRootURL
        try mergeProjects(from: localRoot, into: dataURL, progressHandler: progressHandler)

        FileManager.default.createFile(atPath: Self.enabledMarkerURL.path, contents: nil)
        CrashReportingService.breadcrumb(.sync, "iCloud merge complete")

        await MainActor.run {
            PersistenceService.ensureDirectories()
            NotificationCenter.default.post(name: .iCloudSyncDidEnable, object: dataURL)
        }
    }

    /// Disable iCloud sync: merges iCloud projects back to local, then switches to local.
    @concurrent func disable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        CrashReportingService.breadcrumb(.sync, "Disabling iCloud sync")
        let localRoot = PersistenceService.localRootURL
        try mergeProjects(from: dataURL, into: localRoot, progressHandler: progressHandler)

        try? FileManager.default.removeItem(at: Self.enabledMarkerURL)
        CrashReportingService.breadcrumb(.sync, "Local merge complete")

        await MainActor.run {
            PersistenceService.ensureDirectories()
            NotificationCenter.default.post(name: .iCloudSyncDidDisable, object: nil)
        }
    }

    // MARK: - File Coordination

    /// Read data using NSFileCoordinator.
    func coordinatedRead(from url: URL) -> Data? {
        // Kick a download for not-yet-materialized ubiquitous files so the coordinated read
        // below resolves instead of stalling indefinitely. Idempotent; harmless if already
        // local. Callers run this off the main thread, so blocking until bytes arrive is fine.
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        var coordinatedData: Data?
        var coordinatorError: NSError?
        var readError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            do {
                coordinatedData = try Data(contentsOf: readURL)
            } catch {
                readError = error
            }
        }

        // Unlike the write/delete siblings this can't throw, so callers read a failure as
        // "no such project" — report it here or it's invisible all the way to a blank document.
        if coordinatedData == nil, let error = coordinatorError ?? readError,
           FileManager.default.fileExists(atPath: url.path) {
            CrashReportingService.report(.iCloudCoordinatedReadFailed, error: error, extra: [
                "file": url.lastPathComponent,
                "coordination": coordinatorError != nil,
            ])
        }

        return coordinatedData
    }

    /// Write data using NSFileCoordinator.
    func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?
        var writeError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
            do {
                try data.write(to: writeURL, options: .atomic)
            } catch {
                writeError = error
            }
        }

        if let error = coordinatorError { throw error }
        if let error = writeError { throw error }
    }

    /// Delete a file using NSFileCoordinator.
    func coordinatedDelete(at url: URL) throws {
        var coordinatorError: NSError?
        var deleteError: Error?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { deleteURL in
            do {
                if FileManager.default.fileExists(atPath: deleteURL.path) {
                    try FileManager.default.removeItem(at: deleteURL)
                }
            } catch {
                deleteError = error
            }
        }

        if let error = coordinatorError { throw error }
        if let error = deleteError { throw error }
    }

    // MARK: - Conflict Resolution

    /// Resolve NSFileVersion conflicts on a project's data using last-writer-wins.
    ///
    /// Two separately edited row lists have no defined union, so one of them has to go. The index
    /// is the exception and has its own path — see `resolveIndexConflicts(at:)`.
    func resolveConflicts(at url: URL) {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }

        for conflict in conflicts {
            conflict.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)

        // Last-writer-wins is deliberate, but it discards a peer's edits — warn rather than
        // error, and never name the project (the file name is a UUID or the index).
        CrashReportingService.report(.iCloudConflictDiscardedVersions, extra: [
            "versions": conflicts.count,
            "role": url.lastPathComponent == PersistenceService.indexURL.lastPathComponent ? "index" : "projectData",
        ], level: .warning)
    }

    /// The index is the only copy of a project's *name* on any document last saved before 4.10,
    /// and the only record that a project exists at all. Dropping the losing version of it the way
    /// `resolveConflicts` drops project data means a project created on one device disappears from
    /// every list the moment two devices write the index in the same window — which is what the
    /// ~100 `iCloudConflictDiscardedVersions` events a fortnight were reporting. Union by UUID is
    /// well defined here (`Array<Project>.merged`, tombstone-aware), so nothing has to be lost.
    ///
    /// Returns what it read out of the losing versions rather than writing it: the write path owns
    /// own-write bookkeeping (`recordOwnWrite`/`snapshotAfterWrite`) on the main actor, and a
    /// second writer here would race it.
    func resolveIndexConflicts(at root: URL) -> [Project] {
        let url = PersistenceService.indexURL(at: root)
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return [] }

        // Read before resolving — `removeOtherVersionsOfItem` takes the bytes with it.
        let (recovered, unreadable) = recoveredProjects(fromConflictVersionsAt: conflicts.map(\.url))

        for conflict in conflicts {
            conflict.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)

        // A merged version lost nothing, so it is a breadcrumb. Only a version we could not read
        // is still the old failure, and it is the one worth an issue now that it isn't buried.
        if unreadable > 0 {
            CrashReportingService.report(.iCloudConflictDiscardedVersions, extra: [
                "versions": conflicts.count,
                "unreadable": unreadable,
                "role": "index",
            ], level: .warning)
        } else {
            CrashReportingService.breadcrumb(.sync, "Merged index conflict", data: [
                "versions": conflicts.count,
                "projects": recovered.count,
            ])
        }
        return recovered
    }

    /// Split out from `resolveIndexConflicts` so the part that decides what survives a conflict is
    /// reachable without an NSFileVersion, which a test cannot manufacture.
    ///
    /// Coordinated, like every other read of this file: a conflict version can be a placeholder the
    /// file provider hasn't materialized, and a bare `Data(contentsOf:)` would read that as a
    /// version we can't have — three lines after which the caller deletes it.
    func recoveredProjects(fromConflictVersionsAt urls: [URL]) -> (projects: [Project], unreadable: Int) {
        var recovered: [Project] = []
        var unreadable = 0
        for url in urls {
            guard let data = coordinatedRead(from: url),
                  let index = try? PersistenceService.decoder.decode(ProjectIndex.self, from: data) else {
                unreadable += 1
                continue
            }
            recovered = recovered.merged(with: index.projects)
        }
        return (recovered, unreadable)
    }

    // MARK: - Private

    private func requireIndex(at root: URL, side: String) throws -> ProjectIndex? {
        switch PersistenceService.loadIndex(at: root) {
        case .absent:
            return nil
        case .loaded(let index):
            return index
        case .unreadable:
            CrashReportingService.report(.iCloudMergeSourceUnreadable, extra: ["side": side])
            throw ICloudSyncError.indexUnreadable
        }
    }

    /// Merge projects from source into destination. Union by UUID, last-writer-wins
    /// for projects in both. Project data directories are copied for the winning version.
    private func mergeProjects(
        from source: URL,
        into destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) throws {
        PersistenceService.ensureDirectories(at: destination)

        // An index we merely failed to read must not merge as "no projects" — that writes a
        // merged index missing everything that side held. Absent stays the legitimate empty case.
        let sourceIndex = try requireIndex(at: source, side: "source")
        let destIndex = try requireIndex(at: destination, side: "destination")

        let sourceProjects = sourceIndex?.projects ?? []
        let destProjects = destIndex?.projects ?? []

        let merged = destProjects.merged(with: sourceProjects)

        CrashReportingService.breadcrumb(.sync, "Merging projects", data: [
            "source": sourceProjects.count,
            "destination": destProjects.count,
            "merged": merged.count,
        ])

        guard !merged.isEmpty else {
            progressHandler(1.0)
            return
        }

        // Determine which root has the winning version of each project
        let destIds = Set(destProjects.map(\.id))
        let sourceIds = Set(sourceProjects.map(\.id))
        let destByModDate = Dictionary(destProjects.map { ($0.id, $0.modifiedAt) }, uniquingKeysWith: { a, _ in a })

        for (index, project) in merged.enumerated() {
            // Clean up directory for tombstones, then skip copy logic
            if project.isDeleted {
                PersistenceService.deleteProject(project.id, at: destination)
                progressHandler(Double(index + 1) / Double(merged.count))
                continue
            }

            let sourceWins: Bool
            if !destIds.contains(project.id) {
                // Only in source
                sourceWins = true
            } else if !sourceIds.contains(project.id) {
                // Only in destination — no copy needed
                sourceWins = false
            } else {
                // In both — source wins if it has a newer timestamp
                sourceWins = project.modifiedAt > (destByModDate[project.id] ?? .distantPast)
            }

            if sourceWins {
                try PersistenceService.replaceProjectDir(project.id, from: source, to: destination)
            }
            progressHandler(Double(index + 1) / Double(merged.count))
        }

        let purged = merged.purgingOldTombstones()
        let activeId = purged.first(where: { !$0.isDeleted })?.id
        let mergedIndex = ProjectIndex(
            projects: purged,
            activeProjectId: destIndex?.activeProjectId ?? sourceIndex?.activeProjectId ?? activeId
        )
        try PersistenceService.saveIndex(mergedIndex, at: destination)
    }
}

// MARK: - Errors

enum ICloudSyncError: LocalizedError {
    case containerUnavailable
    case indexUnreadable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return String(localized: "iCloud container is not available. Make sure you're signed into iCloud.")
        case .indexUnreadable:
            return String(localized: "Your project list couldn't be read, so syncing was stopped to avoid losing projects. Check your internet connection and try again.")
        }
    }
}
