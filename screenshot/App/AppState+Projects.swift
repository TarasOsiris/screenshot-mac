import SwiftUI

struct BlankProjectRowConfiguration {
    let label: String?
    let sizePreset: String?
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
                templateCount: nil,
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
            saveError = "Failed to create project from template \"\(template.name)\". The template data could not be loaded."
            return
        }

        projects.append(project)
        switchToProject(project.id)
        saveIndex()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else { return }

        saveCurrentProject()
        switchToProject(id)
        saveIndex()
    }

    func switchToProject(_ id: UUID) {
        undoManager?.removeAllActions()
        projectOpenTask?.cancel()
        beginProjectOpening()
        teardownActiveProject()
        activeProjectId = id
        projectOpenTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.loadProjectContents(for: id)
            self.projectOpenTask = nil
        }
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        guard !trimmed.isEmpty else { return }
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = uniqueProjectName(trimmed, excludingId: id)
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

    func duplicateProject(_ id: UUID) {
        saveCurrentProject()

        guard let source = projects.first(where: { $0.id == id }) else { return }
        let newProject = Project(name: uniqueProjectName(source.name + " Copy"))
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

        // Replace project contents with template data
        PersistenceService.copyProjectFromURL(template.url, to: id)

        // Reload from disk (font registration before row load, matching switchToProject order)
        loadProjectContents(for: id)
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
                // No visible projects left — create a new one
                createProject(name: "Project 1")
                return
            }
        } else {
            PersistenceService.deleteProject(id)
        }
        saveIndex()
    }

    /// Cancels in-flight work, unregisters fonts, and clears images for the current project.
    private func teardownActiveProject() {
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

    private func loadProjectContents(for id: UUID) {
        guard activeProjectId == id else { return }
        loadCustomFonts()
        loadRowsForProject(id)
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
