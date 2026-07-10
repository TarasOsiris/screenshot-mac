import SwiftUI

extension AppState {

    // MARK: - Load

    func load() {
        reloadFromDisk()
    }

    // MARK: - iCloud

    func setupICloudIfNeeded() {
        NotificationCenter.default.addObserver(
            forName: .iCloudSyncDidEnable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let url = notification.object as? URL
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.saveTask?.cancel()
                if let url {
                    self.startICloudMonitoring(at: url)
                }
                self.reloadFromDisk()
            }
        }
        NotificationCenter.default.addObserver(
            forName: .iCloudSyncDidDisable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.saveTask?.cancel()
                self.stopICloudMonitoring()
                self.reloadFromDisk()
            }
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
        monitor.onSyncStatusChange = { [weak self] status in
            self?.iCloudSyncStatus = status
        }
        monitor.startMonitoring(url: url)
        iCloudMonitor = monitor
    }

    func stopICloudMonitoring() {
        iCloudMonitor?.stopMonitoring()
        iCloudMonitor = nil
        iCloudSyncStatus = .idle
    }

    func reloadFromDisk() {
        // The local path reads with plain `Data(contentsOf:)` — fast, no file coordination —
        // so it stays synchronous. The iCloud path can block on undownloaded files and runs
        // off-main to avoid freezing the UI (the freeze when enabling sync with many projects).
        guard PersistenceService.isUsingICloud else {
            reloadLocalFromDisk()
            return
        }
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            await self?.reloadICloudFromDisk()
        }
    }

    private func reloadLocalFromDisk() {
        if let index = PersistenceService.loadIndex() {
            projects = index.projects.purgingOldTombstones()
            selectActiveProjectAfterReload(preferred: index.activeProjectId)
        }
        if let activeId = activeProjectId {
            loadCustomFonts()
            loadRowsForProject(activeId)
            loadScreenshotImages()
        }
        hasCompletedInitialLoad = true
    }

    /// iCloud reload: the blocking coordinated reads (index + active project) run off the main
    /// thread; the in-memory merge and `@Observable` mutations are applied back on the main
    /// actor. `reloadTask` serializes overlapping remote changes so the own-write bookkeeping
    /// (`recordOwnWrite`/`saveIndex`/`snapshotAfterWrite`) never races.
    @MainActor
    private func reloadICloudFromDisk() async {
        let indexURL = PersistenceService.indexURL
        let projectURLs = projects.map { PersistenceService.projectDataURL($0.id) }

        let index = await Task.detached(priority: .userInitiated) { () -> ProjectIndex? in
            let sync = ICloudSyncService.shared
            sync.resolveConflicts(at: indexURL)
            // Resolve conflicts on all known projects, not just the active one, so switching
            // projects later doesn't hit stale conflicts.
            for url in projectURLs { sync.resolveConflicts(at: url) }
            return PersistenceService.loadIndex()
        }.value

        if Task.isCancelled { return }

        if let index {
            if !projects.isEmpty {
                // Tombstone-aware merge: union by UUID, LWW for alive pairs, delete-wins for conflicts.
                let mergedRaw = projects.merged(with: index.projects)
                let changed = mergedRaw != projects
                projects = mergedRaw.purgingOldTombstones()
                // Persist merge result so tombstones propagate back. Keep recordOwnWrite →
                // saveIndex → snapshotAfterWrite together (no await between them).
                if changed {
                    iCloudMonitor?.recordOwnWrite([PersistenceService.indexURL])
                    saveIndex()
                    iCloudMonitor?.snapshotAfterWrite()
                }
            } else {
                projects = index.projects.purgingOldTombstones()
            }
            selectActiveProjectAfterReload(preferred: index.activeProjectId)
        }

        // Set once the index has been processed — independent of the (longer, more cancellable)
        // active-project read below — so an overlapping reload can't strand the loading spinner.
        hasCompletedInitialLoad = true

        guard let activeId = activeProjectId else { return }

        let diskData = await Task.detached(priority: .userInitiated) {
            PersistenceService.loadProject(activeId)
        }.value
        if Task.isCancelled { return }
        // The blocking iCloud read above can outlive a project switch — applying the old
        // project's rows now would let the next save write them into the new project's file.
        guard activeProjectId == activeId else { return }

        if let localModified = activeProjectDataModifiedAt {
            // Only reload if the on-disk version is newer than our in-memory version.
            if let diskData, diskData.modifiedAt > localModified {
                loadCustomFonts()
                applyProjectData(diskData, for: activeId)
                loadScreenshotImages()
            }
        } else {
            loadCustomFonts()
            loadRowsForProject(activeId, preloaded: diskData)
            loadScreenshotImages()
        }
    }

    private func selectActiveProjectAfterReload(preferred: UUID?) {
        let visible = visibleProjects
        guard activeProjectId == nil || !visible.contains(where: { $0.id == activeProjectId }) else { return }
        if let preferred, visible.contains(where: { $0.id == preferred }) {
            activeProjectId = preferred
        } else {
            activeProjectId = visible.first?.id
        }
    }

    /// `deferCleanup` runs the orphaned-resource scan off-main (project-open path) so the
    /// switch doesn't block the push animation; iCloud reload keeps it synchronous.
    func applyProjectData(_ data: ProjectData, for projectId: UUID, deferCleanup: Bool = false) {
        rows = data.rows
        localeState = data.localeState ?? .default
        activeProjectDataModifiedAt = data.modifiedAt
        lastSeenCatalogModified = PersistenceService.translationCatalogModifiedDate(projectId)
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

    /// Re-merge the active project's `translations.xcstrings` when it was edited outside the app
    /// (Xcode's String Catalog editor / a translation tool). Uses the same catalog-wins merge as
    /// `PersistenceService.loadProject`, so text shapes pick up translator edits on re-activation
    /// without a project switch. A no-op when the file is unchanged or the merge changes nothing.
    @MainActor
    func refreshTranslationsIfCatalogChanged() {
        guard let id = activeProjectId,
              let diskModified = PersistenceService.translationCatalogModifiedDate(id),
              diskModified > (lastSeenCatalogModified ?? .distantPast) else { return }
        lastSeenCatalogModified = diskModified

        let updated = TranslationCatalogService.merging(localeState, projectId: id, rows: rows)
        guard updated != localeState else { return }
        localeState = updated
        scheduleSave()
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

    /// Routine save path: never commits in-progress inline/continuous edits (that would create
    /// undo steps on a debounced autosave tick). User-initiated saves go through
    /// `saveCurrentProject`/`flushPendingSavesSynchronously`, which do commit.
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
        let didSaveProject = saveCurrentProject(commitPendingEdits: false)
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
    func saveCurrentProject(commitPendingEdits: Bool = true) -> Bool {
        guard let activeId = activeProjectId else { return true }
        // Don't persist while a project load is in flight: `activeProjectId` already points
        // at the project being opened but `rows` may still belong to the previously active
        // project, so writing now would overwrite the new project's file with stale rows.
        guard projectOpenTask == nil else { return true }
        if commitPendingEdits {
            commitAllPendingEdits()
        }
        let data = ProjectData(rows: rows, localeState: localeState)
        do {
            try PersistenceService.saveProject(activeId, data: data)
            activeProjectDataModifiedAt = data.modifiedAt
            lastSeenCatalogModified = PersistenceService.translationCatalogModifiedDate(activeId)
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
    func saveCurrentProjectAsync(commitPendingEdits: Bool = true) {
        guard let activeId = activeProjectId else { return }
        // See saveCurrentProject(): skip while a load is in flight so we never write the
        // previous project's stale rows into the newly-opened project's file.
        guard projectOpenTask == nil else { return }
        if commitPendingEdits {
            commitAllPendingEdits()
        }
        let data = ProjectData(rows: rows, localeState: localeState)
        activeProjectDataModifiedAt = data.modifiedAt
        let monitor = iCloudMonitor
        monitor?.recordOwnWrite([PersistenceService.projectDataURL(activeId), PersistenceService.translationCatalogURL(activeId)])
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try PersistenceService.saveProject(activeId, data: data)
                let catalogModified = PersistenceService.translationCatalogModifiedDate(activeId)
                await MainActor.run {
                    // A project switch may have landed while we wrote off-main; only stamp the
                    // active-project mtime if it's still the project we just saved.
                    guard let self, self.activeProjectId == activeId else { return }
                    self.lastSeenCatalogModified = catalogModified
                }
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
