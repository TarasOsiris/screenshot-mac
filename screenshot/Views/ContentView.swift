import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isRenamingProject = false
    @State private var renameText = ""
    @State private var isDeletingProject = false
    @State private var keyMonitor: Any?
    @State private var exportSuccessMessage: String?
    @State private var exportSuccessFolderURL: URL?
    @State private var gestureZoomStartLevel: CGFloat?

    private var selectedContextSummary: String {
        if state.selectedShapeId != nil {
            return "Editing shape"
        }
        if let row = state.selectedRow {
            return "Selected: \(row.label)"
        }
        return "\(state.rows.count) row\(state.rows.count == 1 ? "" : "s")"
    }

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
                    if state.projects.count > 1 {
                        Divider()
                        Button("Delete Project...", role: .destructive) {
                            isDeletingProject = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Project actions")
            }

            ToolbarItem(placement: .navigation) {
                ZoomControls()
                    .padding(.leading, 2)
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
                Button {
                    exportScreenshots()
                } label: {
                    Text("Export")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting || state.rows.isEmpty)
                .keyboardShortcut("e", modifiers: .command)
                .help("Export screenshots (\u{2318}E)")
            }

            ToolbarItem(placement: .status) {
                Text(selectedContextSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help("Current editing context")
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
        .alert("Export Complete", isPresented: .init(
            get: { exportSuccessMessage != nil },
            set: {
                if !$0 {
                    exportSuccessMessage = nil
                    exportSuccessFolderURL = nil
                }
            }
        )) {
            Button("OK") { acknowledgeExportSuccess() }
        } message: {
            Text(exportSuccessMessage ?? "")
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
                let trimmedName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = state.activeProjectId, !trimmedName.isEmpty {
                    state.renameProject(id, to: trimmedName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            state.undoManager = undoManager
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
                    state.deleteSelectedShape()
                    return nil
                }

                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                let isCommandShift = flags.contains([.command, .shift]) &&
                    !flags.contains(.option) &&
                    !flags.contains(.control)

                if isCommandShift {
                    if event.keyCode == 30 { // ] key
                        state.bringSelectedShapeToFront()
                        return nil
                    }
                    if event.keyCode == 33 { // [ key
                        state.sendSelectedShapeToBack()
                        return nil
                    }
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
        exportError = nil
        exportSuccessMessage = nil
        exportSuccessFolderURL = nil
        do {
            let projectName = state.activeProject?.name ?? ""
            try ExportService.exportAll(rows: state.rows, projectName: projectName, to: url, screenshotImages: state.screenshotImages)
            let totalScreenshots = state.rows.reduce(0) { $0 + $1.templates.count }
            let exportFolderName = projectName.isEmpty ? "Screenshots" : projectName
            let destinationFolderURL = url.appendingPathComponent(exportFolderName, isDirectory: true)
            let destinationFolder = destinationFolderURL.path
            exportSuccessMessage = "Exported \(totalScreenshots) screenshot\(totalScreenshots == 1 ? "" : "s") to \(destinationFolder)."
            exportSuccessFolderURL = destinationFolderURL
        } catch {
            exportError = error.localizedDescription
            exportSuccessFolderURL = nil
        }
        isExporting = false
    }

    private func acknowledgeExportSuccess() {
        let destinationURL = exportSuccessFolderURL
        exportSuccessMessage = nil
        exportSuccessFolderURL = nil

        guard openExportFolderOnSuccess, let destinationURL else { return }
        NSWorkspace.shared.open(destinationURL)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
