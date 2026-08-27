import SwiftUI

// Writing the document: the debounced save, its synchronous and async variants, the snapshots
// they take, and save-failure reporting.
//
// Several orderings here are load-bearing and are commented at their site: own-write recording
// around each write (so the iCloud monitor doesn't treat our own save as a remote change), the
// projectOpenTask guard in activeProjectSnapshotForSave (so a switch in flight can't write the
// old project's rows into the new project's file), and saveAll passing
// commitPendingEdits: false (so an autosave tick never creates an undo step).
extension AppState {
    /// Shape of the open document, attached to every crash/hang report so a render or export
    /// failure says how much it was chewing on. Counts and enum names only — never project,
    /// row, locale, or text content. Runs on the debounced save tick, not the edit hot path.
    func updateCrashDocumentContext() {
        var templates = 0
        var shapes = 0
        var deviceCategories: Set<String> = []
        var maxRowPixels: CGFloat = 0

        for row in rows {
            templates += row.templates.count
            shapes += row.shapes.count
            maxRowPixels = max(maxRowPixels, row.templateWidth * row.templateHeight * CGFloat(row.templates.count))
            for shape in row.shapes {
                if let category = shape.deviceCategory { deviceCategories.insert(category.rawValue) }
            }
        }

        CrashReportingService.setDocumentContext([
            "rows": rows.count,
            "templates": templates,
            "shapes": shapes,
            "locales": localeState.locales.count,
            "image_resources": screenshotImages.count,
            "device_categories": deviceCategories.sorted(),
            "max_row_pixels": Int(maxRowPixels),
            "zoom": zoom.level,
        ])
    }

    // MARK: - Save failures

    /// Shows the alert *and* reports the failure. Sentry gets the `Error`, never the localized
    /// message — that would fragment one issue across 30 languages.
    func dismissSaveError() {
        saveError = nil
        saveErrorTitle = nil
    }

    /// Shows a titled alert for a user-facing failure that is not a save — a rejected drop,
    /// an unreadable dropped file. Expected user/input failures, so no Sentry event.
    func presentFailure(title: String, message: String) {
        saveErrorTitle = title
        saveError = message
    }

    func reportProjectSaveFailure(_ error: Error) {
        CrashReportingService.report(.projectSaveFailed, error: error)
        saveError = String(localized: "Failed to save project: \(error.localizedDescription)")
    }

    func reportIndexSaveFailure(_ error: Error) {
        CrashReportingService.report(.projectIndexSaveFailed, error: error)
        saveError = String(localized: "Failed to save project index: \(error.localizedDescription)")
    }

    // MARK: - Save

    /// Serial queue for all off-main project writes (debounced autosave and
    /// project-switch saves) so writes can't interleave across concurrency
    /// domains. `flushPendingSaveTask` drains it synchronously on quit.
    static let saveQueue = DispatchQueue(label: "xyz.tleskiv.screenshot.project-save", qos: .utility)

    /// Runs `work` off-main, behind every write already on the save queue. Project reads need
    /// that ordering — switching away and straight back would otherwise open the project as it
    /// stood before the switch — and it is what lets the project-switch save run off-main at all
    /// (a coordinated iCloud write blocks for seconds). No write can slip in between:
    /// `activeProjectSnapshotForSave` declines while a project open is in flight. Only the
    /// barrier occupies the queue, so quit's `saveQueue.sync` never waits on the work itself.
    private static func afterQueuedWrites<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            saveQueue.async { continuation.resume() }
        }
        return await Task.detached(priority: .userInitiated, operation: work).value
    }

    static func loadProjectAfterQueuedWrites(_ id: UUID) async -> ProjectData? {
        await afterQueuedWrites { PersistenceService.loadProject(id) }
    }

    /// Installs a project's files from `url` before reading it — a queued save would otherwise
    /// land on top of what was just installed.
    static func replaceProjectAfterQueuedWrites(_ id: UUID, withProjectAt url: URL) async -> ProjectData? {
        await afterQueuedWrites {
            PersistenceService.copyProjectFromURL(url, to: id)
            return PersistenceService.loadProject(id)
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = .delayed(0.3) { [weak self] in self?.saveAllAsync() }
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
        guard activeId != degradedLoadProjectId else { return nil }
        return (activeId, ProjectData(rows: rows, localeState: localeState))
    }

    /// Debounced-autosave sibling of `saveAll()`: snapshots index + project on the
    /// main actor (cheap COW value copies), then encodes and writes on the serial
    /// save queue — the JSON encode, `.xcstrings` catalog build (with its RTF
    /// decodes), and coordinated iCloud writes no longer hit the main thread on
    /// every edit tick. `flushPendingSaveTask` drains the queue before its
    /// synchronous fallback, so quit can't lose an in-flight write.
    func saveAllAsync() {
        updateCrashDocumentContext()
        sweepUnreachableOrphanedImages()
        let index = makeIndexSnapshotForSave()

        let projectSnapshot = activeProjectSnapshotForSave()

        let monitor = iCloudMonitor
        var ownWriteURLs = [PersistenceService.indexURL]
        if let snapshot = projectSnapshot {
            ownWriteURLs.append(PersistenceService.projectDataURL(snapshot.id))
            ownWriteURLs.append(PersistenceService.translationCatalogURL(snapshot.id))
            inFlightSaveModifiedAt = max(inFlightSaveModifiedAt ?? .distantPast, snapshot.data.modifiedAt)
            inFlightSaveCount += 1
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
                if projectSnapshot != nil {
                    self.inFlightSaveCount -= 1
                    if self.inFlightSaveCount == 0 { self.inFlightSaveModifiedAt = nil }
                }
                // On the main actor to match saveAll's thread for the unlocked snapshot.
                monitor?.snapshotAfterWrite()
                if let indexError {
                    self.reportIndexSaveFailure(indexError)
                }
                if let projectError {
                    self.reportProjectSaveFailure(projectError)
                }
                if let snapshot = projectSnapshot, projectError == nil,
                   self.activeProjectId == snapshot.id {
                    // Stamped only after the write lands (like saveCurrentProject) — an eagerly
                    // stamped failed save would make reloadICloudFromDisk refuse genuinely
                    // newer remote data forever.
                    self.activeProjectDataModifiedAt = snapshot.data.modifiedAt
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
            reportIndexSaveFailure(error)
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
            reportProjectSaveFailure(error)
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
                    self?.reportProjectSaveFailure(error)
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
                    self?.reportIndexSaveFailure(error)
                }
            }
        }
    }
}
