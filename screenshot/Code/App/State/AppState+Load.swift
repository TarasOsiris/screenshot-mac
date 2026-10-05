import SwiftUI

/// Which document replaced the one on screen, which decides whether the resources directory may
/// be swept for orphans.
enum ProjectLoadOrigin {
    /// The user opened or switched projects: what is on screen is what is on disk, so a file the
    /// document doesn't reference really is dead weight.
    case open
    /// An iCloud reload swapped in a remote snapshot. A peer's `project.json` can be newer by
    /// mtime and behind in content, so its references are not a licence to delete anything.
    case remoteReload
}

// Reading the document: first load, iCloud setup and monitoring, reload-from-disk, and applying
// a decoded ProjectData. The writing half is AppState+Save.swift.
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
                CrashReportingService.setTag("icloud", for: "storage")
                AnalyticsService.setProfile([.storage: "icloud"])
                CrashReportingService.breadcrumb(.sync, "iCloud sync enabled")
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
                CrashReportingService.setTag("local", for: "storage")
                AnalyticsService.setProfile([.storage: "local"])
                CrashReportingService.breadcrumb(.sync, "iCloud sync disabled")
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
                CrashReportingService.breadcrumb(.sync, "iCloud container unavailable, using local", level: .warning)
                PersistenceService.ensureDirectories()
                load()
                return
            }

            do {
                try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
            } catch {
                CrashReportingService.report(.directoryCreateFailed, error: error, extra: ["directory": "icloudData"])
            }
            startICloudMonitoring(at: dataURL)

            // Re-tag: `AppState.init` tags `storage` before the container has resolved, so every
            // cold launch reports `local` until this point regardless of the real mode.
            CrashReportingService.setTag("icloud", for: "storage")
            AnalyticsService.setProfile([.storage: "icloud"])

            PersistenceService.ensureDirectories()
            load()
        }
    }

    func startICloudMonitoring(at url: URL) {
        stopICloudMonitoring()

        let monitor = ICloudMonitor(url: url)
        monitor.onRemoteChange = { [weak self] in
            guard let self else { return }
            CrashReportingService.breadcrumb(.sync, "Remote change, reloading", data: ["projects": self.projects.count])
            // Flush any pending save so locally-created projects are persisted
            // before we reload (otherwise the remote index would drop them).
            self.flushPendingSaveTask()
            self.reloadFromDisk()
        }
        monitor.onSyncStatusChange = { [weak self] status in
            self?.iCloudStatus.status = status
        }
        monitor.onResourcesDidChange = { [weak self] in
            self?.reloadUnresolvedScreenshotImages()
        }
        monitor.startMonitoring()
        iCloudMonitor = monitor
    }

    func stopICloudMonitoring() {
        iCloudMonitor?.stopMonitoring()
        iCloudMonitor = nil
        iCloudStatus.status = .idle
    }

    func reloadFromDisk() {
        // Read once and thread it down: the branch below and every root resolved under it must
        // agree about the storage mode, whatever a resolving container does meanwhile.
        let isUsingICloud = PersistenceService.isUsingICloud
        CrashReportingService.breadcrumb(
            .persistence,
            "Reloading from disk",
            data: ["storage": isUsingICloud ? "icloud" : "local", "projects": projects.count]
        )
        // The local path reads with plain `Data(contentsOf:)` — fast, no file coordination —
        // so it stays synchronous. The iCloud path can block on undownloaded files and runs
        // off-main to avoid freezing the UI (the freeze when enabling sync with many projects).
        guard isUsingICloud else {
            reloadLocalFromDisk()
            return
        }
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            await self?.reloadICloudFromDisk(root: PersistenceService.rootURL(isUsingICloud: true))
        }
    }

    /// The index read stays synchronous — it's small, and `activeProjectId` has to be set before
    /// the first frame or the window flashes the "no projects" screen. The active project's own
    /// load goes through the same phased open a switch uses: at launch this runs inside
    /// `AppState.init`, where a synchronous font registration + JSON decode + catalog merge froze
    /// the app with nothing on screen to explain it.
    private func reloadLocalFromDisk() {
        if let loaded = PersistenceService.loadIndexOrRecover() {
            projects = loaded.index.projects.purgingOldTombstones()
            let switched = selectActiveProjectAfterReload(preferred: loaded.index.activeProjectId)
            // Write the rebuild back now: the next launch must not have to recover again, and
            // nothing else here schedules a save.
            if loaded.wasRecovered { saveIndex(at: loaded.root) }
            if switched {
                hasCompletedInitialLoad = true
                return
            }
        }
        hasCompletedInitialLoad = true
        guard let activeId = activeProjectId else { return }
        openProject(activeId) { await AppState.readProjectAfterQueuedWrites(activeId) }
    }

    /// iCloud reload: the blocking coordinated reads (index + active project) run off the main
    /// thread; the in-memory merge and `@Observable` mutations are applied back on the main
    /// actor. `reloadTask` serializes overlapping remote changes so the own-write bookkeeping
    /// (`recordOwnWrite`/`saveIndex`/`snapshotAfterWrite`) never races.
    @MainActor
    private func reloadICloudFromDisk(root: URL) async {
        let projectURLs = projects.map { PersistenceService.projectDataURL($0.id, at: root) }

        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (index: PersistenceService.LoadedIndex?, recoveredFromConflict: [Project]) in
            let sync = ICloudSyncService.shared
            // The index merges its conflicting versions instead of discarding them, and hands back
            // what they held for this function to fold in. Project data can't — see there.
            let recovered = sync.resolveIndexConflicts(at: root)
            // Resolve conflicts on all known projects, not just the active one, so switching
            // projects later doesn't hit stale conflicts.
            for url in projectURLs { sync.resolveConflicts(at: url) }
            return (PersistenceService.loadIndexOrRecover(isUsingICloud: true), recovered)
        }.value

        // Before any early return, and before the index read below is even consulted: the versions
        // this came out of are already deleted, so it exists nowhere else. Both early returns are
        // ordinary — `reloadTask` is cancelled once per remote change during a sync burst, and an
        // iCloud index that reads as absent returns nil rather than rebuilding — and dropping the
        // recovery there would be exactly the loss it was recovered from.
        let adoptedFromConflict = adoptProjectsRecoveredFromConflict(outcome.recoveredFromConflict)

        if Task.isCancelled {
            if adoptedFromConflict { writeIndexBack(at: root) }
            return
        }

        if let loaded = outcome.index {
            // A rebuilt index still has to be written even when it changes nothing in memory:
            // it was reconstructed from the project directories and isn't on disk yet. So does a
            // conflict recovery, which the merge below can't detect — it is already in `projects`.
            var needsWriteBack = loaded.wasRecovered || adoptedFromConflict
            if !projects.isEmpty {
                // Tombstone-aware merge: union by UUID, LWW for alive pairs, delete-wins for
                // conflicts. A rebuild goes through it too — the directories it was built from
                // carry no tombstones, and this is what puts the in-memory ones back.
                let mergedRaw = projects.merged(with: loaded.index.projects)
                needsWriteBack = needsWriteBack || mergedRaw != projects
                projects = mergedRaw.purgingOldTombstones()
            } else {
                projects = loaded.index.projects.purgingOldTombstones()
            }
            // Persist merge result so tombstones propagate back. Keep recordOwnWrite →
            // saveIndex → snapshotAfterWrite together (no await between them). The monitor's own
            // `snapshotAfterWrite` still stamps the live index, so it only suppresses the reload
            // while `loaded.root` is the live root — which is the case this write-back expects.
            if needsWriteBack { writeIndexBack(at: loaded.root) }
            if selectActiveProjectAfterReload(preferred: loaded.index.activeProjectId) {
                hasCompletedInitialLoad = true
                return
            }
        } else if adoptedFromConflict {
            writeIndexBack(at: root)
        }

        // Set once the index has been processed — independent of the (longer, more cancellable)
        // active-project read below — so an overlapping reload can't strand the loading spinner.
        hasCompletedInitialLoad = true

        guard let activeId = activeProjectId else { return }
        // A second apply alongside an open in flight would wipe edits made after the first; run after it instead.
        guard projectOpenTask == nil else {
            reloadDeferredByOpen = true
            return
        }

        // A project not yet read opens like a switch: its overlay goes up before an undownloaded
        // iCloud file blocks for seconds, and saves and reloads wait on `projectOpenTask` meanwhile.
        guard writeStamps.known(for: activeId) != nil else {
            openProject(activeId) { await AppState.readProjectAfterQueuedWrites(activeId) }
            return
        }

        let read = await AppState.readProjectAfterQueuedWrites(activeId)
        if Task.isCancelled { return }
        // The blocking iCloud read above can outlive a project switch — applying the old
        // project's rows now would let the next save write them into the new project's file.
        guard activeProjectId == activeId else { return }

        // Only reload if the on-disk version is newer than our in-memory version. No overlay
        // here: this is a background re-sync of a project already on screen, and the common
        // case is that nothing changed.
        if let diskData = read.data, let localModified = writeStamps.known(for: activeId), diskData.modifiedAt > localModified {
            await loadCustomFontsAsync()
            guard !Task.isCancelled, activeProjectId == activeId else { return }
            applyProjectData(diskData, for: activeId, origin: .remoteReload, readSequence: read.landedSequence)
            loadScreenshotImages()
        }
    }

    /// Takes what `ICloudSyncService.resolveIndexConflicts` read out of the losing versions into
    /// the in-memory list, and answers whether that changed anything — which is also whether the
    /// index on disk is now missing a project, since the caller's own merge can no longer tell.
    @discardableResult
    private func adoptProjectsRecoveredFromConflict(_ recovered: [Project]) -> Bool {
        guard !recovered.isEmpty else { return false }
        let merged = projects.merged(with: recovered)
        guard merged != projects else { return false }
        projects = merged.purgingOldTombstones()
        return true
    }

    /// Keep `recordOwnWrite` → `saveIndex` → `snapshotAfterWrite` together with no await between
    /// them: the monitor suppresses the reload its own write would otherwise trigger by stamping
    /// the file it just wrote.
    private func writeIndexBack(at root: URL) {
        iCloudMonitor?.recordOwnWrite([PersistenceService.indexURL(at: root)])
        saveIndex(at: root)
        iCloudMonitor?.snapshotAfterWrite()
    }

    /// True when it moved off a project that's gone; that runs a full switch, leaving the caller nothing to load.
    @discardableResult
    private func selectActiveProjectAfterReload(preferred: UUID?) -> Bool {
        let visible = visibleProjects
        guard activeProjectId == nil || !visible.contains(where: { $0.id == activeProjectId }) else { return false }
        let next = visible.first { $0.id == preferred }?.id ?? visible.first?.id
        guard activeProjectId != nil else {
            activeProjectId = next
            return false
        }
        if let next { switchToProject(next) } else { closeActiveProject() }
        return true
    }

    /// `readSequence` is the landed writes the read reflects (see `ProjectRead`); nil means "as of now".
    func applyProjectData(_ data: ProjectData, for projectId: UUID, origin: ProjectLoadOrigin, readSequence: Int? = nil) {
        let span = PerfSignpost.begin(
            "AppState.applyProjectData",
            "rows=\(data.rows.count) shapes=\(data.rows.reduce(0) { $0 + $1.shapes.count })"
        )
        defer { PerfSignpost.end("AppState.applyProjectData", span) }
        // The document is replaced wholesale (iCloud/local reload included): a pending debounced
        // edit would flush a stale row over the new data, and any undo step captured against the
        // old rows would restore the pre-reload document — and save it back over the sync.
        presentation.dismissAll()
        cancelPendingDebounceTasks()
        undoManager?.removeAllActions()
        document = ProjectDocument(data)
        writeStamps.recordLoad(
            projectId,
            modifiedAt: data.modifiedAt,
            catalogModified: PersistenceService.translationCatalogModifiedDate(projectId),
            sequence: readSequence ?? ProjectWriteStamps.currentLandedSequence()
        )
        // Drop any preview-mode entries that don't refer to a row in the new data.
        viewMode.reconcilePreviewingRows(against: Set(rows.map(\.id)))
        // The outgoing project's model-resolution rasters are the largest thing the cache holds and
        // will never be asked for again. Gated inside the cache on the project actually changing —
        // the same project is re-applied on every iCloud reload, where its rows are still on screen.
        EditorBlurRasterCache.purgeIfProjectChanged(to: projectId)
        prewarmDeviceModelScenes()
        selectRow(rows.first(where: effectiveVariantFilter.includes)?.id ?? rows.first?.id)
        switch origin {
        case .open:
            viewMode.variantFilter = .all
            cleanupOrphanedResourceFilesAsync(for: projectId)
        case .remoteReload: forgetDeferredOrphans()
        }
        seedAndReclaimFontsForLoadedProject()
        // Otherwise a crash between opening a project and the first save tick carries no document
        // context at all — and "opened a project, then it crashed" is the common report shape.
        updateCrashDocumentContext()
    }

    /// Re-merge the active project's `translations.xcstrings` when it was edited outside the app
    /// (Xcode's String Catalog editor / a translation tool). Uses the same catalog-wins merge as
    /// `PersistenceService.loadProject`, so text shapes pick up translator edits on re-activation
    /// without a project switch. A no-op when the file is unchanged or the merge changes nothing.
    @MainActor
    func refreshTranslationsIfCatalogChanged() {
        guard let id = activeProjectId,
              let diskModified = PersistenceService.translationCatalogModifiedDate(id),
              diskModified > (writeStamps.catalogModified(for: id) ?? .distantPast) else { return }
        writeStamps.recordCatalogModified(id, at: diskModified)

        let updated = TranslationCatalogService.merging(localeState, projectId: id, rows: rows)
        guard updated != localeState else { return }
        localeState = updated
        scheduleSave()
    }

    func loadRowsForProject(_ id: UUID, preloaded: ProjectData? = nil, readSequence: Int? = nil) {
        let span = PerfSignpost.begin("AppState.loadRowsForProject", "preloaded=\(preloaded != nil)")
        defer { PerfSignpost.end("AppState.loadRowsForProject", span) }
        if let data = preloaded ?? PersistenceService.loadProject(id) {
            if degradedLoadProjectId == id { degradedLoadProjectId = nil }
            applyProjectData(data, for: id, origin: .open, readSequence: preloaded == nil ? nil : readSequence)
        } else {
            // The project file exists but wouldn't load. Refusing to save is what stops the next
            // autosave writing this empty fallback over the real data; the alert says why.
            if PersistenceService.projectDataExists(id) {
                CrashReportingService.report(.projectLoadFellBackToEmpty, extra: ["project": id.uuidString])
                degradedLoadProjectId = id
                saveErrorTitle = String(localized: "Project Couldn't Be Opened")
                saveError = String(localized: "This project is shown empty and saving is paused so the original file isn't overwritten. Reopening the app may fix it — otherwise restore from a backup.")
            } else {
                degradedLoadProjectId = nil
            }
            document = ProjectDocument(rows: [makeDefaultRow()])
            writeStamps.forgetLanded()
            selectRow(rows.first?.id)
        }
    }

    /// Parses this document's USDZ models into the shared scene cache ahead of the first render.
    /// `.utility` only orders this behind *pending* work on the queue actor — it cannot preempt a
    /// render already running — so `prewarm` yields between specs to make the ordering real.
    private func prewarmDeviceModelScenes() {
        var specs: [DeviceFrameModelSpec] = []
        for row in rows {
            for shape in row.shapes where shape.type == .device {
                guard let frameId = shape.deviceFrameId,
                      let spec = DeviceFrameCatalog.frame(for: frameId)?.modelSpec,
                      !specs.contains(spec) else { continue }
                specs.append(spec)
            }
        }
        guard !specs.isEmpty else { return }
        Task(priority: .utility) { await DeviceModelSnapshotQueue.shared.prewarm(specs) }
    }
}
