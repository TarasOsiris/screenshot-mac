import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.undoManager) private var undoManager
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportScale") private var exportScale = 1.0
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("lastExportFolderBookmark") private var lastExportFolderBookmark = Data()
    @AppStorage("lastExportFolderPath") private var lastExportFolderPath = ""
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportSuccessTimer: DispatchWorkItem?
    @State private var exportError: String?
    @State private var exportProgress = 0
    @State private var exportTotal = 0
    @State private var isCreatingProject = false
    @State private var isSavingTemplate = false
    @State private var isRenamingProject = false
    @State private var dialogText = ""
    @State private var isDeletingProject = false
    @State private var isResettingProject = false
    @State private var gestureZoomStartLevel: CGFloat?
    @State private var editorViewportHeight: CGFloat = 0
    @State private var scrollWheelMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            LocaleBanner(state: state)
                .alert("Save Failed", isPresented: .init(
                    get: { state.saveError != nil },
                    set: { if !$0 { state.saveError = nil } }
                )) {
                    Button("OK") { state.saveError = nil }
                } message: {
                    Text(state.saveError ?? "")
                }

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
                            state.setZoomLevel(startLevel * value, animated: false)
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
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                editorViewportHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size.height) { _, newValue in
                                editorViewportHeight = newValue
                            }
                    }
                }
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
        .overlay {
            if !state.localeState.isBaseLocale {
                Rectangle()
                    .strokeBorder(Color.localeWarning.opacity(0.5), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        Text("Exporting Screenshots...")
                            .font(.headline)
                        ProgressView(value: Double(exportProgress), total: Double(max(1, exportTotal)))
                            .frame(width: 200)
                        Text("\(exportProgress) of \(exportTotal)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .overlay {
            if !isExporting && state.isLoadingImages {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Loading Images…")
                            .font(.headline)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
        }
        .toolbar(id: "main") {
            ToolbarItem(id: "projectSwitcher", placement: .navigation) {
                projectSwitcherToolbarMenu
            }

            ToolbarItem(id: "projectActions", placement: .navigation) {
                projectActionsToolbarMenu
            }

            ToolbarItem(id: "locale", placement: .navigation) {
                LocaleToolbarMenu(state: state)
            }

            ToolbarItem(id: "export", placement: .principal) {
                exportControlGroup
            }

            ToolbarItem(id: "trailingControls", placement: .primaryAction) {
                HStack(spacing: 6) {
                    ZoomControls(onFit: fitZoomToWindow, fitHelpText: fitZoomHelpText)
                    Divider()
                        .frame(height: 16)
                    inspectorToggleButton
                }
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
            scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.modifierFlags.contains(.command) else { return event }
                let delta = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY * 0.005
                    : event.scrollingDeltaY * 0.05
                state.setZoomLevel(state.zoomLevel + delta, animated: false)
                return nil
            }
        }
        .onDisappear {
            if let monitor = scrollWheelMonitor {
                NSEvent.removeMonitor(monitor)
                scrollWheelMonitor = nil
            }
        }
    }

    @ViewBuilder
    private var projectSwitcherSection: some View {
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
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("projectPicker")
    }

    private var projectSwitcherToolbarMenu: some View {
        Menu {
            projectMenuContent
        } label: {
            projectMenuLabel
        }
        .help(state.activeProject?.name ?? "Switch project")
        .accessibilityIdentifier("projectSwitcherMenu")
    }

    @ViewBuilder
    private var projectMenuContent: some View {
        projectSwitcherSection
    }

    private var projectActionsToolbarMenu: some View {
        Menu {
            Button("New Project...") {
                dialogText = "Project \(state.projects.count + 1)"
                isCreatingProject = true
            }

            templateProjectMenu

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

    private var inspectorToggleButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help(isInspectorPresented ? "Hide inspector" : "Show inspector")
    }

    private var exportButtonLabel: some View {
        HStack(spacing: 4) {
            if isExporting {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else if exportSuccess {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
            } else {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11))
            }
            Text(exportButtonText)
        }
    }

    private var exportControlGroup: some View {
        HStack(spacing: 0) {
            Button {
                exportScreenshots()
            } label: {
                exportButtonLabel
            }
            .keyboardShortcut("e", modifiers: .command)
            .help(exportHelpText)

            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 1, height: 16)

            Menu {
                exportMenuContent
            } label: {
                Label {
                    Text("")
                } icon: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Export options")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(isExporting || state.rows.isEmpty)
    }

    @ViewBuilder
    private var exportMenuContent: some View {
        Button("Choose Folder and Export...") {
            exportScreenshotsAs()
        }

        if hasLastExportDestination {
            Button("Open Export Folder") {
                openLastExportFolder()
            }

            Divider()

            Text(lastExportFolderName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var hasLastExportDestination: Bool {
        !lastExportFolderBookmark.isEmpty
    }

    private var lastExportFolderName: String {
        guard !lastExportFolderPath.isEmpty else { return "selected folder" }
        return URL(fileURLWithPath: lastExportFolderPath).lastPathComponent
    }

    private var exportButtonText: String {
        if isExporting { return "Exporting..." }
        if exportSuccess { return "Exported" }
        return hasLastExportDestination ? "Export" : "Export..."
    }

    private var exportHelpText: String {
        if hasLastExportDestination {
            return "Export screenshots to \(lastExportFolderName) (\u{2318}E)"
        }
        return "Choose a folder and export screenshots (\u{2318}E)"
    }

    private var fitZoomHelpText: String {
        if let row = selectedZoomRow {
            return "Fit \(row.label.isEmpty ? "selected row" : row.label) to the editor"
        }
        return "Fit the selected row to the editor"
    }

    private var selectedZoomRow: ScreenshotRow? {
        if let selectedRowId = state.selectedRowId {
            return state.rows.first(where: { $0.id == selectedRowId })
        }
        return state.rows.first
    }

    private func fitZoomToWindow() {
        guard let row = selectedZoomRow, editorViewportHeight > 0 else { return }
        let baseHeight = row.displayHeight(zoom: 1.0)
        guard baseHeight > 0 else { return }
        state.setZoomLevel(editorViewportHeight / baseHeight)
    }

    private func exportScreenshots() {
        if let savedURL = lastExportFolderURL() {
            exportScreenshots(to: savedURL)
        } else {
            exportScreenshotsAs()
        }
    }

    private func exportScreenshotsAs() {
        guard let url = chooseExportDestination() else { return }
        saveLastExportFolder(url)
        exportScreenshots(to: url)
    }

    private func chooseExportDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Export Screenshots"
        panel.message = "Choose a folder to export screenshots"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    private func exportScreenshots(to url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        guard didAccess else {
            // Permission lost — clear stale bookmark and ask user to pick again
            lastExportFolderBookmark = Data()
            lastExportFolderPath = ""
            exportScreenshotsAs()
            return
        }

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0

        let localeCount = max(1, state.localeState.locales.count)
        exportTotal = localeCount * state.rows.reduce(0) { $0 + $1.templates.count }

        Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isExporting = false
            }
            do {
                let projectName = state.activeProject?.name ?? ""
                let format = ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png
                let destinationFolderURL = try await ExportService.exportAll(
                    rows: state.rows,
                    projectName: projectName,
                    to: url,
                    format: format,
                    scale: CGFloat(exportScale),
                    screenshotImages: state.screenshotImages,
                    localeState: state.localeState,
                    onProgress: { completed in
                        exportProgress = completed
                    }
                )
                exportSuccess = true
                let timer = DispatchWorkItem { exportSuccess = false }
                exportSuccessTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
                if openExportFolderOnSuccess {
                    NSWorkspace.shared.open(destinationFolderURL)
                }
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func lastExportFolderURL() -> URL? {
        guard !lastExportFolderBookmark.isEmpty else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: lastExportFolderBookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveLastExportFolder(url)
            }
            return url
        } catch {
            lastExportFolderBookmark = Data()
            return nil
        }
    }

    private func saveLastExportFolder(_ url: URL) {
        do {
            lastExportFolderBookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            lastExportFolderPath = url.path
        } catch {
            exportError = "Failed to remember export folder: \(error.localizedDescription)"
        }
    }

    private func openLastExportFolder() {
        guard let url = lastExportFolderURL() else { return }
        NSWorkspace.shared.open(url)
    }

}

#Preview {
    ContentView()
        .environment(AppState())
}
