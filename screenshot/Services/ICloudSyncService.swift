import Foundation

/// Manages iCloud Drive sync: container discovery, migration, conflict resolution, and change monitoring.
final class ICloudSyncService: Sendable {
    static let shared = ICloudSyncService()

    private static let containerIdentifier = "iCloud.xyz.tleskiv.screenshot"
    private static let migrationCompleteKey = "iCloudMigrationComplete"

    /// Cached iCloud container URL. Resolved once on background thread.
    /// Access only from main thread after resolveContainer completes.
    nonisolated(unsafe) private var _iCloudURL: URL?
    nonisolated(unsafe) private var _iCloudURLResolved = false

    var iCloudContainerURL: URL? {
        guard _iCloudURLResolved else { return nil }
        return _iCloudURL
    }

    private static let iCloudEnabledKey = "iCloudSyncEnabled"

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.iCloudEnabledKey) == nil
            || UserDefaults.standard.bool(forKey: Self.iCloudEnabledKey)
    }

    var isUsingICloud: Bool {
        isEnabled && iCloudContainerURL != nil
    }

    /// Resolve iCloud container on a background thread, then call completion on main.
    func resolveContainer(completion: @escaping @Sendable (URL?) -> Void) {
        if _iCloudURLResolved {
            completion(_iCloudURL)
            return
        }
        let containerID = Self.containerIdentifier
        Task.detached {
            let url = FileManager.default.url(forUbiquityContainerIdentifier: containerID)
            let docsURL = url?.appendingPathComponent("Documents/screenshot", isDirectory: true)
            if let docsURL {
                try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            }
            await MainActor.run { [weak self] in
                self?._iCloudURL = docsURL
                self?._iCloudURLResolved = true
                completion(docsURL)
            }
        }
    }

    // MARK: - Migration

    /// Migrates local data to iCloud if needed. Call after container is resolved.
    func migrateLocalToICloudIfNeeded(localURL: URL, iCloudURL: URL) {
        guard !UserDefaults.standard.bool(forKey: Self.migrationCompleteKey) else { return }

        let fm = FileManager.default
        let iCloudIndexURL = iCloudURL.appendingPathComponent("projects.json")
        let localIndexURL = localURL.appendingPathComponent("projects.json")

        guard fm.fileExists(atPath: localIndexURL.path) else {
            UserDefaults.standard.set(true, forKey: Self.migrationCompleteKey)
            return
        }

        if fm.fileExists(atPath: iCloudIndexURL.path) {
            mergeLocalIntoICloud(localURL: localURL, iCloudURL: iCloudURL)
        } else {
            copyDirectoryContents(from: localURL, to: iCloudURL)
        }

        UserDefaults.standard.set(true, forKey: Self.migrationCompleteKey)
    }

    private func copyDirectoryContents(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            let destItem = dst.appendingPathComponent(item.lastPathComponent)
            if !fm.fileExists(atPath: destItem.path) {
                try? fm.copyItem(at: item, to: destItem)
            }
        }
    }

    private func mergeLocalIntoICloud(localURL: URL, iCloudURL: URL) {
        let decoder = PersistenceService.decoder
        let encoder = PersistenceService.encoder

        let localIndexURL = localURL.appendingPathComponent("projects.json")
        let iCloudIndexURL = iCloudURL.appendingPathComponent("projects.json")

        guard let localData = try? Data(contentsOf: localIndexURL),
              let localIndex = try? decoder.decode(ProjectIndex.self, from: localData),
              let iCloudData = try? Data(contentsOf: iCloudIndexURL),
              var iCloudIndex = try? decoder.decode(ProjectIndex.self, from: iCloudData) else { return }

        let iCloudProjectIds = Set(iCloudIndex.projects.map(\.id))

        for project in localIndex.projects where !iCloudProjectIds.contains(project.id) {
            iCloudIndex.projects.append(project)

            let localProjectDir = localURL.appendingPathComponent("projects/\(project.id.uuidString)", isDirectory: true)
            let iCloudProjectDir = iCloudURL.appendingPathComponent("projects/\(project.id.uuidString)", isDirectory: true)
            if FileManager.default.fileExists(atPath: localProjectDir.path) &&
               !FileManager.default.fileExists(atPath: iCloudProjectDir.path) {
                try? FileManager.default.copyItem(at: localProjectDir, to: iCloudProjectDir)
            }
        }

        if let mergedData = try? encoder.encode(iCloudIndex) {
            try? mergedData.write(to: iCloudIndexURL, options: .atomic)
        }
    }

    // MARK: - Conflict Resolution

    /// Resolves NSFileVersion conflicts for a project data file.
    static func resolveProjectConflicts(at url: URL) -> ProjectData? {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return nil }

        let decoder = PersistenceService.decoder

        guard let currentData = try? Data(contentsOf: url),
              var merged = try? decoder.decode(ProjectData.self, from: currentData) else {
            resolveAndRemoveConflicts(conflicts)
            return nil
        }

        for conflict in conflicts {
            guard let conflictData = try? Data(contentsOf: conflict.url),
                  let conflictProject = try? decoder.decode(ProjectData.self, from: conflictData) else {
                continue
            }
            merged = mergeProjectData(merged, conflictProject)
        }

        resolveAndRemoveConflicts(conflicts)
        return merged
    }

    /// Resolves NSFileVersion conflicts for the project index.
    static func resolveIndexConflicts(at url: URL) -> ProjectIndex? {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflicts.isEmpty else { return nil }

        let decoder = PersistenceService.decoder

        guard let currentData = try? Data(contentsOf: url),
              var merged = try? decoder.decode(ProjectIndex.self, from: currentData) else {
            resolveAndRemoveConflicts(conflicts)
            return nil
        }

        for conflict in conflicts {
            guard let conflictData = try? Data(contentsOf: conflict.url),
                  let conflictIndex = try? decoder.decode(ProjectIndex.self, from: conflictData) else {
                continue
            }
            merged = mergeProjectIndex(merged, conflictIndex)
        }

        resolveAndRemoveConflicts(conflicts)
        return merged
    }

    private static func resolveAndRemoveConflicts(_ conflicts: [NSFileVersion]) {
        for conflict in conflicts {
            conflict.isResolved = true
        }
        if let first = conflicts.first {
            try? NSFileVersion.removeOtherVersionsOfItem(at: first.url)
        }
    }

    // MARK: - Merge Logic

    /// Merges two ProjectIndex instances by unioning projects by UUID.
    static func mergeProjectIndex(_ a: ProjectIndex, _ b: ProjectIndex) -> ProjectIndex {
        var projectsById: [UUID: Project] = [:]

        for project in a.projects {
            projectsById[project.id] = project
        }

        for project in b.projects {
            if let existing = projectsById[project.id] {
                if project.modifiedAt > existing.modifiedAt {
                    projectsById[project.id] = project
                }
            } else {
                projectsById[project.id] = project
            }
        }

        var merged: [Project] = []
        var seen = Set<UUID>()
        for project in a.projects {
            if let p = projectsById[project.id] {
                merged.append(p)
                seen.insert(project.id)
            }
        }
        for project in b.projects where !seen.contains(project.id) {
            if let p = projectsById[project.id] {
                merged.append(p)
            }
        }

        let aMaxModified = a.projects.map(\.modifiedAt).max() ?? .distantPast
        let bMaxModified = b.projects.map(\.modifiedAt).max() ?? .distantPast
        let activeId = bMaxModified > aMaxModified ? (b.activeProjectId ?? a.activeProjectId) : a.activeProjectId

        return ProjectIndex(projects: merged, activeProjectId: activeId)
    }

    /// Merges two ProjectData instances. Uses whole-project last-modified-wins.
    static func mergeProjectData(_ a: ProjectData, _ b: ProjectData) -> ProjectData {
        if b.modifiedAt > a.modifiedAt {
            return b
        }
        return a
    }
}
