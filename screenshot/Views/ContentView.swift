import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isCreatingProject = false
    @State private var isSavingTemplate = false
    @State private var isRenamingProject = false
    @State private var dialogText = ""
    @State private var isDeletingProject = false
    @State private var isResettingProject = false
    @State private var gestureZoomStartLevel: CGFloat?

    var body: some View {
        VStack(spacing: 0) {
            LocaleBanner(state: state)

            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(state.rows) { row in
                            EditorRowView(state: state, row: row)
                                .id(row.id)
                            Divider()
                        }

                        AddRowButton {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.addRow()
                            }
                        }
                    }
                }
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { value in
                            let startLevel = gestureZoomStartLevel ?? state.zoomLevel
                            if gestureZoomStartLevel == nil {
                                gestureZoomStartLevel = startLevel
                            }
                            state.zoomLevel = min(
                                ZoomConstants.max,
                                max(ZoomConstants.min, startLevel * value)
                            )
                        }
                        .onEnded { _ in
                            gestureZoomStartLevel = nil
                        }
                )
                .onChange(of: state.canvasFocusRequestNonce) { _, _ in
                    guard let rowId = state.canvasFocusRowId else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(rowId, anchor: .center)
                    }
                    state.canvasFocusRowId = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(0)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            // Shape properties bottom bar
            if state.selectedShapeId != nil {
                Divider()
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.selectedShapeId != nil)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    projectMenuContent
                } label: {
                    projectMenuLabel
                }
                .help(state.activeProject?.name ?? "No Project")
                .accessibilityIdentifier("projectActionsMenu")
            }

            ToolbarItem(placement: .navigation) {
                LocaleToolbarMenu(state: state)
            }

            ToolbarItem(placement: .navigation) {
                ZoomControls()
                    .padding(.leading, 2)
            }

            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            ToolbarItem(placement: .automatic) {
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 16)
                    .padding(.horizontal, 8)
                    .accessibilityLabel("Screenshot Bro")
            }

            ToolbarItem(placement: .automatic) {
                Spacer()
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(isInspectorPresented ? "Hide inspector" : "Show inspector")
            }

            ToolbarItem(placement: .primaryAction) {
                Button("Export") {
                    exportScreenshots()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isExporting || state.rows.isEmpty)
                .keyboardShortcut("e", modifiers: .command)
                .help("Export screenshots (\u{2318}E)")
            }

        }
        .toolbarRole(.editor)
        .alert("Export Failed", isPresented: .init(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .alert("Reset Project", isPresented: $isResettingProject) {
            Button("Reset", role: .destructive) {
                if let id = state.activeProjectId {
                    state.resetProject(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to reset \"\(state.activeProject?.name ?? "")\"? All rows and shapes will be removed. This cannot be undone.")
        }
        .alert("Delete Project", isPresented: $isDeletingProject) {
            Button("Delete", role: .destructive) {
                if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(state.activeProject?.name ?? "")\"? This cannot be undone.")
        }
        .alert("Rename Project", isPresented: $isRenamingProject) {
            TextField("Project name", text: $dialogText.limited(to: 100))
            Button("Rename") {
                if let id = state.activeProjectId {
                    state.renameProject(id, to: dialogText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New Project", isPresented: $isCreatingProject) {
            TextField("Project name", text: $dialogText.limited(to: 100))
            Button("Create") {
                state.createProject(name: dialogText)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Save as Template", isPresented: $isSavingTemplate) {
            TextField("Template name", text: $dialogText.limited(to: 100))
            Button("Save") {
                state.saveCurrentProjectAsTemplate(name: dialogText)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save the current project as a reusable template.")
        }
        .onAppear {
            state.undoManager = undoManager
            undoManager?.levelsOfUndo = 50
        }
    }

    @ViewBuilder
    private var projectMenuContent: some View {
        projectSwitcherSection

        Divider()

        Button("New Project...") {
            dialogText = "Project \(state.projects.count + 1)"
            isCreatingProject = true
        }

        templateProjectMenu

        Divider()

        currentProjectSection
    }

    @ViewBuilder
    private var projectSwitcherSection: some View {
        Section("Switch Project") {
            ForEach(state.projects) { project in
                Button {
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
    }

    @ViewBuilder
    private var templateProjectMenu: some View {
        Menu("New Project from Template") {
            if state.projectTemplates.isEmpty {
                Button("No Saved Templates") {}
                    .disabled(true)
            } else {
                ForEach(state.projectTemplates) { template in
                    Button(template.name) {
                        state.createProject(fromTemplate: template.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var currentProjectSection: some View {
        Section("Current Project") {
            Button("Save as Template...") {
                dialogText = state.activeProject?.name ?? ""
                isSavingTemplate = true
            }
            .disabled(state.activeProjectId == nil)

            Button("Rename Project...") {
                dialogText = state.activeProject?.name ?? ""
                isRenamingProject = true
            }
            .disabled(state.activeProjectId == nil)

            Button("Duplicate Project") {
                if let id = state.activeProjectId {
                    state.duplicateProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Reset Project...", role: .destructive) {
                if confirmBeforeDeleting {
                    isResettingProject = true
                } else if let id = state.activeProjectId {
                    state.resetProject(id)
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Delete Project...", role: .destructive) {
                if confirmBeforeDeleting {
                    isDeletingProject = true
                } else if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            .disabled(state.activeProjectId == nil || state.projects.count <= 1)
        }
    }

    private var projectMenuLabel: some View {
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

    private func exportScreenshots() {
        let panel = NSOpenPanel()
        panel.title = "Export Screenshots"
        panel.message = "Choose a folder to export screenshots"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        isExporting = true
        exportError = nil
        do {
            let projectName = state.activeProject?.name ?? ""
            let format = ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png
            let destinationFolderURL = try ExportService.exportAll(
                rows: state.rows,
                projectName: projectName,
                to: url,
                format: format,
                scale: CGFloat(exportScale),
                screenshotImages: state.screenshotImages,
                localeState: state.localeState
            )
            if openExportFolderOnSuccess {
                NSWorkspace.shared.open(destinationFolderURL)
            }
        } catch {
            exportError = error.localizedDescription
        }
        isExporting = false
    }

}

#Preview {
    ContentView()
        .environment(AppState())
}
