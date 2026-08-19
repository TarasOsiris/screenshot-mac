import SwiftUI

struct BlankProjectRowConfiguration {
    let label: String?
    let sizePreset: String?
    let templateCount: Int?
    let deviceCategory: DeviceCategory?
    let deviceFrameId: String?
}

extension AppState {

    // MARK: - Projects

    func createProject(name: String) {
        createBlankProject(name: name, rowConfigurations: [])
    }

    func createBlankProject(name: String, rowConfigurations: [BlankProjectRowConfiguration]) {
        saveCurrentProject()

        let sanitized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        let baseName = sanitized.isEmpty ? "Project" : sanitized
        let project = Project(name: uniqueProjectName(baseName))
        projects.append(project)
        activeProjectId = project.id
        PersistenceService.ensureProjectDirs(project.id)
        cancelPendingDebounceTasks()
        let configuredRows = rowConfigurations.enumerated().map { index, configuration in
            let fallbackLabel = rowLabel(for: configuration, rowIndex: index)
            let resolvedSize = configuration.sizePreset.flatMap(parseSizeString)
            return makeDefaultRow(
                label: fallbackLabel,
                width: resolvedSize?.width,
                height: resolvedSize?.height,
                templateCount: configuration.templateCount,
                defaultDeviceCategory: configuration.deviceCategory,
                defaultDeviceFrameId: configuration.deviceFrameId
            )
        }
        rows = configuredRows.isEmpty ? [makeDefaultRow()] : configuredRows
        localeState = .default
        selectRow(rows.first?.id)
        CrashReportingService.breadcrumb(.project, "Created blank project", data: ["rows": rows.count])
        saveAll()
    }

    func createProjectFromTemplate(_ template: ProjectTemplate, name: String? = nil) {
        saveCurrentProject()

        let trimmed = name.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength)) } ?? ""
        let baseName = trimmed.isEmpty ? template.name : trimmed
        let project = Project(name: uniqueProjectName(baseName))
        let copied = PersistenceService.copyProjectFromURL(template.url, to: project.id)

        // Verify the template data can be loaded before committing
        guard copied, PersistenceService.loadProject(project.id) != nil else {
            PersistenceService.deleteProject(project.id)
            // A bundled template that copies but won't load is entirely our bug — the id is ours,
            // not user content. A failed copy already reported itself with the underlying error;
            // raising this second, error-less issue would just split one cause across two.
            if copied {
                CrashReportingService.report(.bundledTemplateLoadFailed, extra: ["template": template.id])
            }
            saveError = String(localized: "Failed to create project from template \"\(template.name)\". The template data could not be loaded.")
            return
        }

        CrashReportingService.breadcrumb(.project, "Created project from template", data: ["template": template.id])
        projects.append(project)
        switchToProject(project.id)
        saveIndex()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else {
            // The switch is a no-op (already active), but a caller (the iPad open gate) may
            // have optimistically set the opening flag — clear it so nothing waits forever
            // for a switch that won't happen.
            finishProjectOpening()
            return
        }

        // Write the OLD project while activeProjectId still points at it, then switch, then
        // persist the index so it records the NEW activeProjectId. Both writes are file-
        // coordinated under iCloud, where they block for seconds, so neither may run on the
        // click's runloop turn — `loadProjectAfterQueuedWrites` is what keeps the switch's
        // read behind them.
        saveCurrentProjectAsync()
        switchToProject(id)
        saveIndexAsync()
    }

    func switchToProject(_ id: UUID) {
        CrashReportingService.breadcrumb(.project, "Switching project", data: ["projects": projects.count])
        undoManager?.removeAllActions()
        projectOpenTask?.cancel()
        beginProjectOpening()
        teardownActiveProject()
        activeProjectId = id
        openProject(id) { await AppState.loadProjectAfterQueuedWrites(id) }
    }

    /// The second half of every project transition: read the project off the main thread — so
    /// the loading spinner keeps animating and a large project.json doesn't freeze the project
    /// list — then apply it here if the transition is still current.
    private func openProject(_ id: UUID, loading load: @escaping @Sendable () async -> ProjectData?) {
        projectOpenTask = Task { @MainActor [weak self] in
            let data = await load()
            guard let self, !Task.isCancelled, self.activeProjectId == id else { return }
            // Let the push + spinner paint a frame before the heavy `rows = …` rebuild,
            // so the loader animates instead of freezing mid-transition.
            await Task.yield()
            guard !Task.isCancelled, self.activeProjectId == id else { return }
            await self.loadProjectContents(for: id, preloaded: data)
            self.projectOpenTask = nil
        }
    }

    func setASCAppId(_ ascAppId: String?, forProject id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        guard projects[idx].ascAppId != ascAppId else { return }
        projects[idx].ascAppId = ascAppId
        scheduleSave()
    }

    func setGooglePlayPackageName(_ packageName: String?, forProject id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        guard projects[idx].googlePlayPackageName != packageName else { return }
        projects[idx].googlePlayPackageName = packageName
        scheduleSave()
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        guard !trimmed.isEmpty else { return }
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = uniqueProjectName(trimmed, excludingId: id)
            CrashReportingService.breadcrumb(.project, "Renamed project")
            scheduleSave()
        }
    }

    func setProjectStarred(_ id: UUID, _ starred: Bool) {
        if let idx = projects.firstIndex(where: { $0.id == id }), projects[idx].isStarred != starred {
            projects[idx].isStarred = starred
            projects[idx].modifiedAt = Date()
            scheduleSave()
        }
    }

    func uniqueProjectName(_ baseName: String, excludingId: UUID? = nil) -> String {
        let existingNames = Set(visibleProjects.filter { $0.id != excludingId }.map { $0.name })
        return Self.uniqueName(baseName, among: existingNames)
    }

    static func uniqueName(_ baseName: String, among existingNames: Set<String>) -> String {
        let cappedBase = String(baseName.prefix(maxProjectNameLength))
        if !existingNames.contains(cappedBase) { return cappedBase }
        var counter = 2
        while true {
            let suffix = " \(counter)"
            let availableCount = max(0, maxProjectNameLength - suffix.count)
            let candidate = String(cappedBase.prefix(availableCount)) + suffix
            if !existingNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
    }

    func duplicateProject(_ id: UUID, name: String? = nil) {
        saveCurrentProject()

        guard let source = projects.first(where: { $0.id == id }) else { return }
        let trimmed = name.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength)) } ?? ""
        let chosenName = trimmed.isEmpty ? source.name + " Copy" : trimmed
        let newProject = Project(name: uniqueProjectName(chosenName))
        CrashReportingService.breadcrumb(.project, "Duplicating project", data: ["rows": rows.count])
        PersistenceService.copyProject(from: id, to: newProject.id)
        projects.append(newProject)

        switchToProject(newProject.id)
        saveIndex()
    }

    func resetProject(_ id: UUID) {
        guard id == activeProjectId else { return }
        CrashReportingService.breadcrumb(.project, "Reset project")
        undoManager?.removeAllActions()
        teardownActiveProject()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func resetProjectFromTemplate(_ id: UUID, template: ProjectTemplate) {
        guard id == activeProjectId else { return }
        CrashReportingService.breadcrumb(.project, "Reset project from template", data: ["template": template.id])
        undoManager?.removeAllActions()
        projectOpenTask?.cancel()
        beginProjectOpening()
        teardownActiveProject()

        openProject(id) { await AppState.replaceProjectAfterQueuedWrites(id, withProjectAt: template.url) }
    }

    func deleteProject(_ id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].markDeleted()
        CrashReportingService.breadcrumb(.project, "Deleted project", data: ["was_active": activeProjectId == id])

        if activeProjectId == id {
            teardownActiveProject()
            PersistenceService.deleteProject(id)
            if let nextProject = visibleProjects.first {
                switchToProject(nextProject.id)
            } else {
                // No visible projects left — drop to the empty "Create Project" state.
                deselectAll()
                rows = []
                viewMode.reconcilePreviewingRows(against: [])
                localeState = .default
                activeProjectId = nil
                activeProjectDataModifiedAt = nil
            }
        } else {
            PersistenceService.deleteProject(id)
        }
        saveIndex()
    }

    /// Cancels in-flight work, unregisters fonts, and clears images for the current project.
    private func teardownActiveProject() {
        textEdit.isActive = false
        cancelPendingDebounceTasks()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        unregisterCustomFonts()
        screenshotImages = [:]
    }

    func beginProjectOpening() {
        isOpeningProject = true
    }

    func finishProjectOpening() {
        isOpeningProject = false
    }

    private func loadProjectContents(for id: UUID, preloaded: ProjectData?) async {
        await loadCustomFontsAsync()
        guard activeProjectId == id else { return }
        loadRowsForProject(id, preloaded: preloaded)
        // The chrome (locale bar, row headers) and canvas only need the project
        // *structure* — rows + localeState — which is now applied. Reveal the UI
        // immediately so a project with many languages / large images doesn't keep
        // the whole window behind a loading overlay. Images stream in afterwards
        // (the canvas renders placeholders until each one is ready).
        finishProjectOpening()
        loadScreenshotImages()
    }

    private func rowLabel(for configuration: BlankProjectRowConfiguration, rowIndex: Int) -> String? {
        if let explicit = configuration.label?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return explicit
        }
        if let frameId = configuration.deviceFrameId,
           let frame = DeviceFrameCatalog.frame(for: frameId) {
            return frame.modelName
        }
        if let deviceCategory = configuration.deviceCategory {
            return deviceCategory.label
        }
        return rowIndex == 0 ? nil : "Row \(rowIndex + 1)"
    }
}
