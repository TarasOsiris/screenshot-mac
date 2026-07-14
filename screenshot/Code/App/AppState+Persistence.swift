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

    /// Serial queue for all off-main project writes (debounced autosave and
    /// project-switch saves) so writes can't interleave across concurrency
    /// domains. `flushPendingSaveTask` drains it synchronously on quit.
    static let saveQueue = DispatchQueue(label: "xyz.tleskiv.screenshot.project-save", qos: .utility)

    func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveAllAsync()
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

    /// Builds the index snapshot for a save, stamping the active project's
    /// `modifiedAt` (skipping tombstones). Shared by every sync/async index save.
    private func makeIndexSnapshotForSave() -> ProjectIndex {
        if let idx = projects.firstIndex(where: { $0.id == activeProjectId && !$0.isDeleted }) {
            projects[idx].modifiedAt = Date()
        }
        return ProjectIndex(projects: projects, activeProjectId: activeProjectId)
    }

    /// Snapshot of the active project for a save (a cheap COW value copy), or nil
    /// while a project load is in flight: `activeProjectId` already points at the
    /// project being opened but `rows` may still belong to the previously active
    /// project, so writing now would overwrite the new project's file with stale
    /// rows. Shared by every sync/async project save.
    private func activeProjectSnapshotForSave() -> (id: UUID, data: ProjectData)? {
        guard let activeId = activeProjectId, projectOpenTask == nil else { return nil }
        return (activeId, ProjectData(rows: rows, localeState: localeState))
    }

    /// Debounced-autosave sibling of `saveAll()`: snapshots index + project on the
    /// main actor (cheap COW value copies), then encodes and writes on the serial
    /// save queue — the JSON encode, `.xcstrings` catalog build (with its RTF
    /// decodes), and coordinated iCloud writes no longer hit the main thread on
    /// every edit tick. `flushPendingSaveTask` drains the queue before its
    /// synchronous fallback, so quit can't lose an in-flight write.
    func saveAllAsync() {
        let index = makeIndexSnapshotForSave()

        let projectSnapshot = activeProjectSnapshotForSave()
        if let snapshot = projectSnapshot {
            activeProjectDataModifiedAt = snapshot.data.modifiedAt
        }

        let monitor = iCloudMonitor
        var ownWriteURLs = [PersistenceService.indexURL]
        if let snapshot = projectSnapshot {
            ownWriteURLs.append(PersistenceService.projectDataURL(snapshot.id))
            ownWriteURLs.append(PersistenceService.translationCatalogURL(snapshot.id))
        }
        monitor?.recordOwnWrite(ownWriteURLs)

        Self.saveQueue.async { [weak self] in
            var indexError: Error?
            var projectError: Error?
            var catalogModified: Date?
            do { try PersistenceService.saveIndex(index) } catch { indexError = error }
            if let snapshot = projectSnapshot {
                do {
                    try PersistenceService.saveProject(snapshot.id, data: snapshot.data)
                    catalogModified = PersistenceService.translationCatalogModifiedDate(snapshot.id)
                } catch { projectError = error }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                // On the main actor to match saveAll's thread for the unlocked snapshot.
                monitor?.snapshotAfterWrite()
                if let indexError {
                    self.saveError = String(localized: "Failed to save project index: \(indexError.localizedDescription)")
                }
                if let projectError {
                    self.saveError = String(localized: "Failed to save project: \(projectError.localizedDescription)")
                }
                if let snapshot = projectSnapshot, projectError == nil,
                   self.activeProjectId == snapshot.id {
                    self.lastSeenCatalogModified = catalogModified
                }
                if indexError == nil && projectError == nil {
                    self.cleanupUnreferencedFontsThrottled()
                }
            }
        }
    }

    @discardableResult
    func saveIndex() -> Bool {
        let index = makeIndexSnapshotForSave()
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
        guard activeProjectId != nil, projectOpenTask == nil else { return true }
        if commitPendingEdits {
            commitAllPendingEdits()
        }
        guard let snapshot = activeProjectSnapshotForSave() else { return true }
        do {
            try PersistenceService.saveProject(snapshot.id, data: snapshot.data)
            activeProjectDataModifiedAt = snapshot.data.modifiedAt
            lastSeenCatalogModified = PersistenceService.translationCatalogModifiedDate(snapshot.id)
            return true
        } catch {
            saveError = String(localized: "Failed to save project: \(error.localizedDescription)")
            return false
        }
    }

    /// Snapshots the active project's data on the main actor and encodes+writes it
    /// off-main, so switching projects doesn't block the push animation. Must be
    /// called while `activeProjectId` still points at the project being saved.
    func saveCurrentProjectAsync(commitPendingEdits: Bool = true) {
        guard activeProjectId != nil, projectOpenTask == nil else { return }
        if commitPendingEdits {
            commitAllPendingEdits()
        }
        guard let (activeId, data) = activeProjectSnapshotForSave() else { return }
        activeProjectDataModifiedAt = data.modifiedAt
        let monitor = iCloudMonitor
        monitor?.recordOwnWrite([PersistenceService.projectDataURL(activeId), PersistenceService.translationCatalogURL(activeId)])
        Self.saveQueue.async { [weak self] in
            do {
                try PersistenceService.saveProject(activeId, data: data)
                let catalogModified = PersistenceService.translationCatalogModifiedDate(activeId)
                DispatchQueue.main.async {
                    // A project switch may have landed while we wrote off-main; only stamp the
                    // active-project mtime if it's still the project we just saved.
                    guard let self, self.activeProjectId == activeId else { return }
                    self.lastSeenCatalogModified = catalogModified
                }
            } catch {
                DispatchQueue.main.async {
                    self?.saveError = String(localized: "Failed to save project: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Off-main sibling of `saveIndex()` — snapshots `ProjectIndex` on main, writes detached.
    func saveIndexAsync() {
        let index = makeIndexSnapshotForSave()
        let monitor = iCloudMonitor
        monitor?.recordOwnWrite([PersistenceService.indexURL])
        Self.saveQueue.async { [weak self] in
            do {
                try PersistenceService.saveIndex(index)
                // Snapshot AFTER the write completes so hasIndexChanged() treats it as our
                // own save and the iCloud monitor doesn't trigger a reload (mirrors saveAll).
                // On the main actor to match saveAll's thread for the unlocked snapshot.
                DispatchQueue.main.async { monitor?.snapshotAfterWrite() }
            } catch {
                DispatchQueue.main.async {
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
