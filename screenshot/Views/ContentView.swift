import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isRenamingProject = false
    @State private var renameText = ""
    @State private var isDeletingProject = false
    @State private var isResettingProject = false
    @State private var gestureZoomStartLevel: CGFloat?

    private var projectSelectionBinding: Binding<UUID?> {
        Binding(
            get: { state.activeProjectId },
            set: { newValue in
                guard let newValue else { return }
                state.selectProject(newValue)
            }
        )
    }

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            LocaleBanner(state: state)

            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(state.rows) { row in
                        EditorRowView(state: state, row: row)
                        Divider()
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addRow()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("Add Row")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderless)
                    .help("Add row")
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(0)
            .background(Color(nsColor: .windowBackgroundColor))

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
                Picker("Project", selection: projectSelectionBinding) {
                    ForEach(state.projects) { project in
                        Text(project.name).tag(Optional(project.id))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 200)
                .help("Select project")
                .accessibilityIdentifier("projectPicker")
            }

            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("New Project...") {
                        state.createProject(name: "Project \(state.projects.count + 1)")
                    }
                    Button("Rename Project...") {
                        renameText = state.activeProject?.name ?? ""
                        isRenamingProject = true
                    }
                    .disabled(state.activeProjectId == nil)
                    Divider()
                    Button("Reset Project...", role: .destructive) {
                        isResettingProject = true
                    }
                    .disabled(state.activeProjectId == nil)
                    if state.projects.count > 1 {
                        Button("Delete Project...", role: .destructive) {
                            isDeletingProject = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Project actions")
                .accessibilityIdentifier("projectActionsMenu")
            }

            ToolbarItem(placement: .navigation) {
                ZoomControls()
                    .padding(.leading, 2)
            }

            ToolbarItem(placement: .navigation) {
                LocaleToolbarMenu(state: state)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.addRow()
                    }
                } label: {
                    Label("Add Row", systemImage: "plus")
                }
                .disabled(state.activeProjectId == nil)
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .help("Add row (\u{21e7}\u{2318}R)")
                .accessibilityIdentifier("toolbarAddRowButton")
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
            TextField("Project name", text: $renameText.limited(to: 50))
            Button("Rename") {
                let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = state.activeProjectId, !trimmedName.isEmpty {
                    state.renameProject(id, to: trimmedName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            state.undoManager = undoManager
            undoManager?.levelsOfUndo = 50
        }
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
