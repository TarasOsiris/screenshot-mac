import SwiftUI

extension AppState {

    // MARK: - Projects

    func createProject(name: String) {
        saveCurrentProject()

        let sanitized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        let baseName = sanitized.isEmpty ? "Project" : sanitized
        let project = Project(name: uniqueProjectName(baseName))
        projects.append(project)
        activeProjectId = project.id
        PersistenceService.ensureProjectDirs(project.id)
        cancelPendingDebounceTasks()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func createProjectFromTemplate(_ template: ProjectTemplate) {
        saveCurrentProject()

        let project = Project(name: uniqueProjectName(template.name))
        PersistenceService.copyProjectFromURL(template.url, to: project.id)
        projects.append(project)

        switchToProject(project.id)
        saveAll()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else { return }

        saveCurrentProject()
        switchToProject(id)
        saveIndex()
    }

    func switchToProject(_ id: UUID) {
        undoManager?.removeAllActions()
        cancelPendingDebounceTasks()
        unregisterCustomFonts()
        activeProjectId = id
        screenshotImages.removeAll()
        loadCustomFonts()
        loadRowsForProject(id)
        loadScreenshotImages()
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
        saveAll()
    }

    func resetProject(_ id: UUID) {
        guard id == activeProjectId else { return }
        undoManager?.removeAllActions()
        cancelPendingDebounceTasks()
        unregisterCustomFonts()
        screenshotImages.removeAll()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func deleteProject(_ id: UUID) {
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[idx].markDeleted()
        PersistenceService.deleteProject(id)

        if activeProjectId == id {
            cancelPendingDebounceTasks()
            unregisterCustomFonts()
            screenshotImages.removeAll()
            if let nextProject = visibleProjects.first {
                activeProjectId = nextProject.id
                loadRowsForProject(nextProject.id)
                loadScreenshotImages()
                loadCustomFonts()
            } else {
                // No visible projects left — create a new one
                createProject(name: "Project 1")
                return
            }
        }
        saveAll()
    }
}
