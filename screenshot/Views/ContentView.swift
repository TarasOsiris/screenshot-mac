import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isRenamingProject = false
    @State private var renameText = ""
    @State private var isDeletingProject = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
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
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

            // Shape properties bottom bar
            if state.selectedShapeId != nil {
                Divider()
                ShapePropertiesBar(state: state)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.selectedShapeId != nil)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isInspectorPresented.toggle()
                        } label: {
                            Image(systemName: "sidebar.trailing")
                        }
                    }
                }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    ForEach(state.projects) { project in
                        Button {
                            state.selectProject(project.id)
                        } label: {
                            HStack {
                                Text(project.name)
                                if project.id == state.activeProjectId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Rename Project...") {
                        renameText = state.activeProject?.name ?? ""
                        isRenamingProject = true
                    }
                    Button("New Project...") {
                        state.createProject(name: "Project \(state.projects.count + 1)")
                    }
                    if state.projects.count > 1 {
                        Divider()
                        Button("Delete Project", role: .destructive) {
                            isDeletingProject = true
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(state.activeProject?.name ?? "No Project")
                            .font(.system(size: 12))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                }
            }

            ToolbarItem(placement: .navigation) {
                HStack(spacing: 4) {
                    Button {
                        state.zoomLevel = max(0.25, state.zoomLevel - 0.25)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(state.zoomLevel <= 0.25)

                    Slider(value: $state.zoomLevel, in: 0.25...2.0, step: 0.25)
                        .frame(width: 80)
                        .controlSize(.small)

                    Button {
                        state.zoomLevel = min(2.0, state.zoomLevel + 0.25)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(state.zoomLevel >= 2.0)

                    Button {
                        state.zoomLevel = 1.0
                    } label: {
                        Text(verbatim: "\(Int(state.zoomLevel * 100))%")
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(state.zoomLevel == 1.0 ? .tertiary : .secondary)
                            .frame(width: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset to 100%")
                }
                .padding(.leading, 8)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportScreenshots()
                } label: {
                    Text("Export")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
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
            TextField("Project name", text: $renameText)
            Button("Rename") {
                if let id = state.activeProjectId, !renameText.isEmpty {
                    state.renameProject(id, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
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
        do {
            try ExportService.exportAll(rows: state.rows, projectName: state.activeProject?.name ?? "Screenshots", to: url)
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
