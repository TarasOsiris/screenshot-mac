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

    private init() {
        // Migrate from UserDefaults (which syncs across Macs) to local marker file
        let legacyKey = "iCloudSyncEnabled"
        if UserDefaults.standard.bool(forKey: legacyKey) {
            let fm = FileManager.default
            let dir = PersistenceService.localRootURL
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: Self.enabledMarkerURL.path, contents: nil)
            UserDefaults.standard.removeObject(forKey: legacyKey)
        }
    }

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

    /// Enable iCloud sync: copies local data to iCloud container, posts notification.
    func enable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        if iCloudContainerURL == nil {
            _ = await resolveContainer()
        }
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        try copyDataDirectory(from: PersistenceService.localRootURL, to: dataURL, progressHandler: progressHandler)

        // Create marker file in the local directory (per-machine, never synced)
        let markerURL = Self.enabledMarkerURL
        FileManager.default.createFile(atPath: markerURL.path, contents: nil)

        await MainActor.run {
            PersistenceService.ensureDirectories()
            NotificationCenter.default.post(name: .iCloudSyncDidEnable, object: dataURL)
        }
    }

    /// Disable iCloud sync: copies iCloud data back to local, posts notification.
    func disable(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard let dataURL = iCloudDataURL else {
            throw ICloudSyncError.containerUnavailable
        }

        try copyDataDirectory(from: dataURL, to: PersistenceService.localRootURL, progressHandler: progressHandler)

        // Remove marker file
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

    private func copyDataDirectory(
        from source: URL,
        to destination: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else {
            progressHandler(1.0)
            return
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(fileURL)
            }
        }

        guard !files.isEmpty else {
            progressHandler(1.0)
            return
        }

        let sourcePathCount = source.path.count
        for (index, fileURL) in files.enumerated() {
            let relativePath = String(fileURL.path.dropFirst(sourcePathCount))
            let destURL = destination.appendingPathComponent(relativePath)

            let destDir = destURL.deletingLastPathComponent()
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: fileURL, to: destURL)

            progressHandler(Double(index + 1) / Double(files.count))
        }
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
