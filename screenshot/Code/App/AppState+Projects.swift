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
        saveAll()
    }

    func createProjectFromTemplate(_ template: ProjectTemplate, name: String? = nil) {
        saveCurrentProject()

        let trimmed = name.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength)) } ?? ""
        let baseName = trimmed.isEmpty ? template.name : trimmed
        let project = Project(name: uniqueProjectName(baseName))
        PersistenceService.copyProjectFromURL(template.url, to: project.id)

        // Verify the template data can be loaded before committing
        guard PersistenceService.loadProject(project.id) != nil else {
            PersistenceService.deleteProject(project.id)
            saveError = String(localized: "Failed to create project from template \"\(template.name)\". The template data could not be loaded.")
            return
        }

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

        #if os(macOS)
        // Synchronous write-before-read: the detached write below can lose a race with a
        // quick switch-back (stale read of the old project) and is dropped on immediate
        // quit. macOS has no push animation to keep smooth, so save inline.
        saveCurrentProject()
        switchToProject(id)
        saveIndex()
        #else
        // Snapshot + write the OLD project off-main while activeProjectId still points at
        // it (and before switchToProject sets projectOpenTask), then switch. switchToProject
        // sets the opening flag. saveIndexAsync runs AFTER the switch so the index persists
        // the NEW activeProjectId (matching the old synchronous order). Keeps the disk
        // encode/write off the runloop turn that animates the iPad push.
        saveCurrentProjectAsync()
        switchToProject(id)
        saveIndexAsync()
        #endif
    }

    func switchToProject(_ id: UUID) {
        undoManager?.removeAllActions()
        projectOpenTask?.cancel()
        beginProjectOpening()
        teardownActiveProject()
        activeProjectId = id
        projectOpenTask = Task { @MainActor [weak self] in
            // Decode off the main thread so the loading spinner keeps animating and
            // the project list (iPad) doesn't freeze while a large project.json is read.
            let data = await Task.detached(priority: .userInitiated) {
                PersistenceService.loadProject(id)
            }.value
            guard let self, !Task.isCancelled, self.activeProjectId == id else { return }
            // Let the push + spinner paint a frame before the heavy `rows = …` rebuild,
            // so the loader animates instead of freezing mid-transition.
            await Task.yield()
            guard !Task.isCancelled, self.activeProjectId == id else { return }
            self.loadProjectContents(for: id, preloaded: data)
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
        PersistenceService.copyProject(from: id, to: newProject.id)
        projects.append(newProject)

        switchToProject(newProject.id)
        saveIndex()
    }

    func resetProject(_ id: UUID) {
        guard id == activeProjectId else { return }
        undoManager?.removeAllActions()
        teardownActiveProject()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func resetProjectFromTemplate(_ id: UUID, template: ProjectTemplate) {
        guard id == activeProjectId else { return }
        undoManager?.removeAllActions()
        beginProjectOpening()
        teardownActiveProject()

        PersistenceService.copyProjectFromURL(template.url, to: id)

        // Reload from disk (font registration before row load, matching switchToProject order)
        loadProjectContents(for: id, preloaded: PersistenceService.loadProject(id))
    }

    func deleteProject(_ id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].markDeleted()

        if activeProjectId == id {
            teardownActiveProject()
            PersistenceService.deleteProject(id)
            if let nextProject = visibleProjects.first {
                switchToProject(nextProject.id)
            } else {
                // No visible projects left — drop to the empty "Create Project" state.
                deselectAll()
                rows = []
                reconcilePreviewingRows(against: [])
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
        isEditingText = false
        cancelPendingDebounceTasks()
        imageLoadTask?.cancel()
        imageLoadTask = nil
        isLoadingImages = false
        unregisterCustomFonts()
        screenshotImages = [:]
    }

    func beginProjectOpening() {
        isOpeningProject = true
    }

    func finishProjectOpening() {
        isOpeningProject = false
    }

    private func loadProjectContents(for id: UUID, preloaded: ProjectData?) {
        guard activeProjectId == id else { return }
        loadCustomFonts()
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
