import StoreKit
import SwiftUI

extension ContentView {
    var sortedProjects: [Project] {
        if projectSortOrder == "alphabetical" {
            return state.visibleProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return state.visibleProjects
    }

    @ViewBuilder
    var projectSwitcherSection: some View {
        ForEach(sortedProjects) { project in
            Button {
                guard project.id != state.activeProjectId else { return }
                state.selectProject(project.id)
            } label: {
                if project.id == state.activeProjectId {
                    Label(project.name, systemImage: "checkmark")
                } else {
                    Text(project.name)
                }
            }
        }
    }

    @ViewBuilder
    var currentProjectSection: some View {
        Section("Current Project") {
            Button("Rename Project...", systemImage: "pencil") {
                guard let id = state.activeProjectId else { return }
                let currentName = state.activeProject?.name ?? ""
                // Defer so the menu fully dismisses before the modal opens.
                Task { @MainActor in
                    presentProjectNameAlert(
                        title: String(localized: "Rename Project"),
                        confirmTitle: String(localized: "Rename"),
                        initialValue: currentName
                    ) { newName in
                        state.renameProject(id, to: newName)
                    }
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Duplicate Project...", systemImage: "plus.square.on.square") {
                store.requirePro(
                    allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
                    context: .projectLimit
                ) {
                    guard let id = state.activeProjectId else { return }
                    let initialName = (state.activeProject?.name ?? "") + " Copy"
                    Task { @MainActor in
                        presentProjectNameAlert(
                            title: String(localized: "Duplicate Project"),
                            confirmTitle: String(localized: "Duplicate"),
                            initialValue: initialName
                        ) { newName in
                            state.duplicateProject(id, name: newName)
                        }
                    }
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Show in Finder", systemImage: "folder") {
                guard let id = state.activeProjectId else { return }
                let folder = PersistenceService.projectDirectoryURL(id)
                PlatformReveal.inFileViewer([folder])
            }
            .disabled(state.activeProjectId == nil)

            Button("Reset Project...", systemImage: "arrow.counterclockwise", role: .destructive) {
                if confirmBeforeDeleting {
                    isResettingProject = true
                } else if let id = state.activeProjectId {
                    state.resetProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)

            resetFromTemplateMenu

            Button("Delete Project...", systemImage: "trash", role: .destructive) {
                if confirmBeforeDeleting {
                    isDeletingProject = true
                } else if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)
        }
    }

    func presentProjectNameAlert(
        title: String,
        confirmTitle: String,
        initialValue: String,
        onConfirm: @escaping (String) -> Void
    ) {
        projectNamePrompt = ProjectNamePrompt(
            title: title,
            confirmTitle: confirmTitle,
            initialValue: initialValue,
            onConfirm: onConfirm
        )
    }

    @ViewBuilder
    var resetFromTemplateMenu: some View {
        if !projectTemplates.isEmpty {
            Menu("Reset Project from Template", systemImage: "doc.on.doc") {
                ForEach(projectTemplates) { template in
                    Button {
                        resetTemplate = template
                        if confirmBeforeDeleting {
                            isResettingProject = true
                        } else if let id = state.activeProjectId {
                            state.resetProjectFromTemplate(id, template: template)
                            resetTemplate = nil
                        }
                    } label: {
                        Label {
                            Text(template.name)
                        } icon: {
                            if let icon = template.menuIcon {
                                Image(nsImage: icon)
                            }
                        }
                    }
                }
            }
            .disabled(state.activeProjectId == nil)
        }
    }

    var projectMenuLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(state.activeProject?.name ?? "No Project")
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 320, alignment: .leading)
        }
        .accessibilityIdentifier("projectPicker")
    }

    var projectSwitcherToolbarMenu: some View {
        Menu {
            projectMenuContent
        } label: {
            projectMenuLabel
        }
        .menuStyle(.button)
        .help(state.activeProject?.name ?? String(localized: "Switch project"))
        .accessibilityIdentifier("projectSwitcherMenu")
    }

    @ViewBuilder
    var projectMenuContent: some View {
        projectSwitcherSection
    }

    var projectActionsToolbarMenu: some View {
        Menu {
            Button("New Project...", systemImage: "plus") {
                store.requirePro(
                    allowed: store.canCreateProject(currentCount: state.visibleProjects.count),
                    context: .projectLimit
                ) {
                    openWindow(id: NewProjectWindowView.windowID)
                }
            }

            Divider()

            currentProjectSection
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("Project actions")
        .accessibilityIdentifier("projectActionsMenu")
    }

    var inspectorToggleButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help(isInspectorPresented ? String(localized: "Hide inspector") : String(localized: "Show inspector"))
    }

    #if os(iOS)
    // iPad zoom is two standard-sized toolbar buttons (same tap target as the other nav-bar
    // buttons) rather than the compact macOS ZoomControls cluster, which is too small to tap.
    var iPadZoomOutButton: some View {
        Button {
            state.zoomOut()
        } label: {
            Label("Zoom Out", systemImage: "minus.magnifyingglass")
        }
        .disabled(state.zoomLevel <= ZoomConstants.min)
        .help("Zoom out")
    }

    var iPadZoomInButton: some View {
        Button {
            state.zoomIn()
        } label: {
            Label("Zoom In", systemImage: "plus.magnifyingglass")
        }
        .disabled(state.zoomLevel >= ZoomConstants.max)
        .help("Zoom in")
    }

    var iPadUndoButton: some View {
        Button {
            undoManager?.undo()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
        }
        .disabled(!(undoManager?.canUndo ?? false))
        .help("Undo")
    }

    var iPadRedoButton: some View {
        Button {
            undoManager?.redo()
        } label: {
            Label("Redo", systemImage: "arrow.uturn.forward")
        }
        .disabled(!(undoManager?.canRedo ?? false))
        .help("Redo")
    }
    #endif
}
