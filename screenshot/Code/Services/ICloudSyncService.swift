import Foundation

extension Notification.Name {
    static let iCloudSyncDidEnable = Notification.Name("iCloudSyncDidEnable")
    static let iCloudSyncDidDisable = Notification.Name("iCloudSyncDidDisable")
}

final class ICloudSyncService: @unchecked Sendable {
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

    /// The active root URL for project storage.
    var activeRootURL: URL {
        if isUsingICloud, let url = iCloudDataURL {
            return url
        }
        return PersistenceService.localRootURL
    }

    private init() {}

    // MARK: - Container Resolution

    /// Resolve the iCloud container URL. Must be called off the main thread.
    func resolveContainer() async -> URL? {
        let url = await Task.detached {
            FileManager.default.url(forUbiquityContainerIdentifier: self.containerID)
        }.value
        containerLock.lock()
        _iCloudContainerURL = url
        containerLock.unlock()
        return url
    }

    // MARK: - Enable / Disable

    /// Enable iCloud sync: merges local projects into iCloud, then switches to iCloud.
    func enable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        if iCloudContainerURL == nil {
            _ = await resolveContainer()
        }
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        let localRoot = PersistenceService.localRootURL
        try mergeProjects(from: localRoot, into: dataURL, progressHandler: progressHandler)

        FileManager.default.createFile(atPath: Self.enabledMarkerURL.path, contents: nil)

        await MainActor.run {
            PersistenceService.ensureDirectories()
            NotificationCenter.default.post(name: .iCloudSyncDidEnable, object: dataURL)
        }
    }

    /// Disable iCloud sync: merges iCloud projects back to local, then switches to local.
    func disable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        let localRoot = PersistenceService.localRootURL
        try mergeProjects(from: dataURL, into: localRoot, progressHandler: progressHandler)

        try? FileManager.default.removeItem(at: Self.enabledMarkerURL)

        await MainActor.run {
            PersistenceService.ensureDirectories()
            NotificationCenter.default.post(name: .iCloudSyncDidDisable, object: nil)
        }
    }

    // MARK: - File Coordination

    /// Read data using NSFileCoordinator.
    func coordinatedRead(from url: URL) -> Data? {
        var coordinatedData: Data?
        var coordinatorError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            coordinatedData = try? Data(contentsOf: readURL)
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

    // MARK: - Conflict Resolution

    /// Resolve NSFileVersion conflicts using last-writer-wins strategy.
    func resolveConflicts(at url: URL) {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return }

        for conflict in conflicts {
            conflict.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    // MARK: - Private

    /// Merge projects from source into destination. Union by UUID, last-writer-wins
    /// for projects in both. Project data directories are copied for the winning version.
    private func mergeProjects(
        from source: URL,
        into destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) throws {
        PersistenceService.ensureDirectories(at: destination)

        let sourceIndex = PersistenceService.loadIndex(at: source)
        let destIndex = PersistenceService.loadIndex(at: destination)

        let sourceProjects = sourceIndex?.projects ?? []
        let destProjects = destIndex?.projects ?? []

        let merged = destProjects.merged(with: sourceProjects)

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

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            return "iCloud container is not available. Make sure you're signed into iCloud."
        }
    }
}
