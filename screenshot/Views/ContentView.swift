import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isRenamingProject = false
    @State private var renameText = ""
    @State private var isDeletingProject = false
    @State private var isDeletingShape = false
    @State private var keyMonitor: Any?

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
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
                ZoomControls(zoomLevel: $state.zoomLevel)
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
        .alert("Delete Shape", isPresented: $isDeletingShape) {
            Button("Delete", role: .destructive) {
                state.deleteSelectedShape()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this shape?")
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
        .onAppear {
            // Remove any existing monitor to guard against double-registration
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Don't intercept when a text field has focus
                if let responder = event.window?.firstResponder,
                   responder.isKind(of: NSText.self) {
                    return event
                }

                guard state.selectedShapeId != nil else { return event }

                if event.keyCode == 51 { // Delete key
                    isDeletingShape = true
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
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

// MARK: - Zoom Controls

enum ZoomConstants {
    static let min: CGFloat = 0.25
    static let max: CGFloat = 2.0
    static let step: CGFloat = 0.25
}

private struct ZoomControls: View {
    @Binding var zoomLevel: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            zoomButton("minus", disabled: zoomLevel <= ZoomConstants.min) {
                zoomLevel = Swift.max(ZoomConstants.min, zoomLevel - ZoomConstants.step)
            }

            Slider(value: $zoomLevel, in: ZoomConstants.min...ZoomConstants.max, step: ZoomConstants.step)
                .frame(width: 80)
                .controlSize(.small)

            zoomButton("plus", disabled: zoomLevel >= ZoomConstants.max) {
                zoomLevel = Swift.min(ZoomConstants.max, zoomLevel + ZoomConstants.step)
            }

            Button {
                zoomLevel = 1.0
            } label: {
                Text(verbatim: "\(Int(zoomLevel * 100))%")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(zoomLevel == 1.0 ? .tertiary : .secondary)
                    .frame(width: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reset to 100%")
        }
    }

    private func zoomButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(disabled)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
