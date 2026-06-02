import SwiftUI

extension AppState {

    // MARK: - Load

    func load() {
        reloadFromDisk()

        if visibleProjects.isEmpty {
            let project = Project(name: "My App")
            projects = [project]
            activeProjectId = project.id
            PersistenceService.ensureProjectDirs(project.id)
            rows = [makeDefaultRow()]
            selectRow(rows.first?.id)
            saveAll()
        }
    }

    // MARK: - iCloud

    func setupICloudIfNeeded() {
        NotificationCenter.default.addObserver(
            forName: .iCloudSyncDidEnable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            self.saveTask?.cancel()
            if let url = notification.object as? URL {
                self.startICloudMonitoring(at: url)
            }
            self.reloadFromDisk()
        }
        NotificationCenter.default.addObserver(
            forName: .iCloudSyncDidDisable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.saveTask?.cancel()
            self.stopICloudMonitoring()
            self.reloadFromDisk()
        }

        let sync = ICloudSyncService.shared
        guard sync.isEnabled else { return }

        Task {
            _ = await sync.resolveContainer()
            guard let dataURL = sync.iCloudDataURL else {
                // Container resolution failed — fall back to local
                PersistenceService.ensureDirectories()
                load()
                return
            }

            try? FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            startICloudMonitoring(at: dataURL)

            PersistenceService.ensureDirectories()
            load()
        }
    }

    func startICloudMonitoring(at url: URL) {
        stopICloudMonitoring()

        let monitor = ICloudMonitor()
        monitor.onRemoteChange = { [weak self] in
            guard let self else { return }
            // Flush any pending save so locally-created projects are persisted
            // before we reload (otherwise the remote index would drop them).
            self.flushPendingSaveTask()
            self.reloadFromDisk()
        }
        monitor.startMonitoring(url: url)
        iCloudMonitor = monitor
    }

    func stopICloudMonitoring() {
        iCloudMonitor?.stopMonitoring()
        iCloudMonitor = nil
    }

    func reloadFromDisk() {
        // Resolve conflicts on iCloud files before reading
        if PersistenceService.isUsingICloud {
            ICloudSyncService.shared.resolveConflicts(at: PersistenceService.indexURL)
            // Resolve conflicts on all known projects, not just the active one,
            // so switching projects later doesn't hit stale conflicts.
            for project in projects {
                ICloudSyncService.shared.resolveConflicts(at: PersistenceService.projectDataURL(project.id))
            }
        }

        if let index = PersistenceService.loadIndex() {
            if PersistenceService.isUsingICloud && !projects.isEmpty {
                // Tombstone-aware merge: union by UUID with LWW + resurrection semantics.
                let mergedRaw = projects.merged(with: index.projects)
                let changed = mergedRaw != projects
                projects = mergedRaw.purgingOldTombstones()
                // Persist merge result so tombstones propagate back
                if changed {
                    iCloudMonitor?.recordOwnWrite([PersistenceService.indexURL])
                    saveIndex()
                    iCloudMonitor?.snapshotAfterWrite()
                }
            } else {
                projects = index.projects.purgingOldTombstones()
            }
            let visible = visibleProjects
            if activeProjectId == nil || !visible.contains(where: { $0.id == activeProjectId }) {
                if let preferredId = index.activeProjectId,
                   visible.contains(where: { $0.id == preferredId }) {
                    activeProjectId = preferredId
                } else {
                    activeProjectId = visible.first?.id
                }
            }
        }

        if let activeId = activeProjectId {
            if PersistenceService.isUsingICloud, let localModified = activeProjectDataModifiedAt {
                // Only reload if the on-disk version is newer than our in-memory version
                if let diskData = PersistenceService.loadProject(activeId),
                   diskData.modifiedAt > localModified {
                    loadCustomFonts()
                    applyProjectData(diskData, for: activeId)
                    loadScreenshotImages()
                }
            } else {
                loadCustomFonts()
                loadRowsForProject(activeId)
                loadScreenshotImages()
            }
        }
    }

    /// `deferCleanup` runs the orphaned-resource scan off-main (project-open path) so the
    /// switch doesn't block the push animation; iCloud reload keeps it synchronous.
    func applyProjectData(_ data: ProjectData, for projectId: UUID, deferCleanup: Bool = false) {
        rows = data.rows
        localeState = data.localeState ?? .default
        activeProjectDataModifiedAt = data.modifiedAt
        // Drop any preview-mode entries that don't refer to a row in the new data.
        reconcilePreviewingRows(against: Set(rows.map(\.id)))
        selectRow(rows.first?.id)
        if deferCleanup {
            cleanupOrphanedResourceFilesAsync(for: projectId)
        } else {
            cleanupOrphanedResourceFiles(for: projectId)
        }
        seedReferencedFontFamiliesFromLoadedProject()
    }

    // MARK: - Save

    func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveAll()
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    func saveAll() {
        // Record own writes so iCloud monitor ignores them
        if let monitor = iCloudMonitor {
            var urls = [PersistenceService.indexURL]
            if let activeId = activeProjectId {
                urls.append(PersistenceService.projectDataURL(activeId))
            }
            monitor.recordOwnWrite(urls)
        }

        let didSaveIndex = saveIndex()
        let didSaveProject = saveCurrentProject()
        if didSaveIndex && didSaveProject {
            cleanupUnreferencedFonts()
        }

        // Snapshot AFTER writing so hasIndexChanged() returns false for our own saves
        iCloudMonitor?.snapshotAfterWrite()
    }

    @discardableResult
    func saveIndex() -> Bool {
        // Update modifiedAt for the active project (skip tombstones)
        if let idx = projects.firstIndex(where: { $0.id == activeProjectId && !$0.isDeleted }) {
            projects[idx].modifiedAt = Date()
        }
        let index = ProjectIndex(projects: projects, activeProjectId: activeProjectId)
        do {
            try PersistenceService.saveIndex(index)
            return true
        } catch {
            saveError = String(localized: "Failed to save project index: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func saveCurrentProject() -> Bool {
        guard let activeId = activeProjectId else { return true }
        // Don't persist while a project load is in flight: `activeProjectId` already points
        // at the project being opened but `rows` may still belong to the previously active
        // project, so writing now would overwrite the new project's file with stale rows.
        guard projectOpenTask == nil else { return true }
        let data = ProjectData(rows: rows, localeState: localeState)
        do {
            try PersistenceService.saveProject(activeId, data: data)
            activeProjectDataModifiedAt = data.modifiedAt
            return true
        } catch {
            saveError = String(localized: "Failed to save project: \(error.localizedDescription)")
            return false
        }
    }

    /// Snapshots the active project's data on the main actor (a cheap value copy of
    /// rows/localeState) and encodes+writes it off-main, so switching projects doesn't
    /// block the push animation. Must be called while `activeProjectId` still points at the
    /// project being saved.
    func saveCurrentProjectAsync() {
        guard let activeId = activeProjectId else { return }
        // See saveCurrentProject(): skip while a load is in flight so we never write the
        // previous project's stale rows into the newly-opened project's file.
        guard projectOpenTask == nil else { return }
        let data = ProjectData(rows: rows, localeState: localeState)
        activeProjectDataModifiedAt = data.modifiedAt
        let monitor = iCloudMonitor
        monitor?.recordOwnWrite([PersistenceService.projectDataURL(activeId)])
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try PersistenceService.saveProject(activeId, data: data)
            } catch {
                await MainActor.run {
                    self?.saveError = String(localized: "Failed to save project: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Off-main sibling of `saveIndex()` — snapshots `ProjectIndex` on main, writes detached.
    func saveIndexAsync() {
        if let idx = projects.firstIndex(where: { $0.id == activeProjectId && !$0.isDeleted }) {
            projects[idx].modifiedAt = Date()
        }
        let index = ProjectIndex(projects: projects, activeProjectId: activeProjectId)
        let monitor = iCloudMonitor
        monitor?.recordOwnWrite([PersistenceService.indexURL])
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try PersistenceService.saveIndex(index)
                // Snapshot AFTER the write completes so hasIndexChanged() treats it as our
                // own save and the iCloud monitor doesn't trigger a reload (mirrors saveAll).
                // On the main actor to match saveAll's thread for the unlocked snapshot.
                await MainActor.run { monitor?.snapshotAfterWrite() }
            } catch {
                await MainActor.run {
                    self?.saveError = String(localized: "Failed to save project index: \(error.localizedDescription)")
                }
            }
        }
    }

    func loadRowsForProject(_ id: UUID, preloaded: ProjectData? = nil) {
        if let data = preloaded ?? PersistenceService.loadProject(id) {
            applyProjectData(data, for: id, deferCleanup: true)
        } else {
            rows = [makeDefaultRow()]
            localeState = .default
            activeProjectDataModifiedAt = nil
            selectRow(rows.first?.id)
        }
    }
}
