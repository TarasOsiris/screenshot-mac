import SwiftUI
import UniformTypeIdentifiers
import RevenueCatUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @Environment(\.undoManager) private var undoManager
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("lastExportFolderBookmark") private var lastExportFolderBookmark = Data()
    @AppStorage("lastExportFolderPath") private var lastExportFolderPath = ""
    @AppStorage("projectSortOrder") private var projectSortOrder = "creation"
    @State private var isInspectorPresented = true
    @State private var isExporting = false
    @State private var exportSuccess = false
    @State private var exportSuccessTimer: DispatchWorkItem?
    @State private var exportError: String?
    @State private var exportProgress = 0
    @State private var exportTotal = 0
    @State private var exportTask: Task<Void, Never>?
    @State private var isCreatingProject = false
    @State private var isCreatingFromTemplate = false
    @State private var pendingTemplate: ProjectTemplate?
    @State private var isRenamingProject = false
    @State private var dialogText = ""
    @State private var isDeletingProject = false
    @State private var isResettingProject = false
    @State private var resetTemplate: ProjectTemplate?
    @State private var projectTemplates: [ProjectTemplate] = TemplateService.availableTemplates()
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
                            store.requirePro(
                                allowed: store.canAddRow(currentCount: state.rows.count),
                                context: .rowLimit
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.addRow()
                                }
                            }
                        }
                    }
                }
                .id(state.activeProjectId)
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
                    if state.canvasFocusAnimated {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(rowId, anchor: .center)
                        }
                    } else {
                        proxy.scrollTo(rowId, anchor: .center)
                        state.canvasFocusAnimated = true
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
            if state.hasSelection {
                Divider()
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.hasSelection)
        .onExitCommand {
            if state.hasSelection {
                state.selectedShapeIds = []
            } else if state.selectedRowId != nil {
                state.deselectAll()
            }
        }
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
                        Button("Cancel") {
                            exportTask?.cancel()
                        }
                        .keyboardShortcut(.cancelAction)
                        .controlSize(.small)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .overlay {
            if !isExporting && (state.isOpeningProject || state.isLoadingImages) {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(state.isOpeningProject ? "Opening Project…" : "Loading Images…")
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
                    .padding(.leading, 8)
            }

            ToolbarItem(id: "projectActions", placement: .navigation) {
                projectActionsToolbarMenu
            }

            ToolbarItem(id: "locale", placement: .navigation) {
                LocaleToolbarMenu(state: state)
                    .padding(.trailing, 8)
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
        .alert(resetTemplate != nil ? "Reset Project from Template" : "Reset Project", isPresented: $isResettingProject) {
            Button("Reset", role: .destructive) {
                if let id = state.activeProjectId {
                    if let template = resetTemplate {
                        state.resetProjectFromTemplate(id, template: template)
                        resetTemplate = nil
                    } else {
                        state.resetProject(id)
                    }
                }
            }
            Button("Cancel", role: .cancel) { resetTemplate = nil }
        } message: {
            if let template = resetTemplate {
                Text("Are you sure you want to reset \"\(state.activeProject?.name ?? "")\" using the \"\(template.name)\" template? All current rows and shapes will be replaced. This cannot be undone.")
            } else {
                Text("Are you sure you want to reset \"\(state.activeProject?.name ?? "")\"? All rows and shapes will be removed. This cannot be undone.")
            }
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
        .alert("New Project from Template", isPresented: $isCreatingFromTemplate) {
            TextField("Project name", text: $dialogText.limited(to: 100))
            Button("Create") {
                if let template = pendingTemplate {
                    state.createProjectFromTemplate(template, name: dialogText)
                    pendingTemplate = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingTemplate = nil }
        }
        .sheet(isPresented: Binding(get: { store.showPaywall }, set: { _ in store.dismissPaywall() })) {
            paywallSheet
        }
        .middleMousePan()
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

    private var sortedProjects: [Project] {
        if projectSortOrder == "alphabetical" {
            return state.visibleProjects.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return state.visibleProjects
    }

    @ViewBuilder
    private var projectSwitcherSection: some View {
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
    private var currentProjectSection: some View {
        Section("Current Project") {
            Button("Rename Project...") {
                dialogText = state.activeProject?.name ?? ""
                // Defer to next tick so menu dismisses before alert presents
                Task { @MainActor in
                    isRenamingProject = true
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Duplicate Project") {
                store.requirePro(
                    allowed: store.canCreateProject(),
                    context: .projectLimit
                ) {
                    if let id = state.activeProjectId {
                        state.duplicateProject(id)
                    }
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

            resetFromTemplateMenu

            Button("Delete Project...", role: .destructive) {
                if confirmBeforeDeleting {
                    isDeletingProject = true
                } else if let id = state.activeProjectId {
                    state.deleteProject(id)
                }
            }
            .disabled(state.activeProjectId == nil || state.visibleProjects.count <= 1)
        }
    }

    @ViewBuilder
    private var resetFromTemplateMenu: some View {
        if !projectTemplates.isEmpty {
            Menu("Reset Project from Template") {
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
                            if let nsImage = template.previewImage {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            }
                        }
                    }
                }
            }
            .disabled(state.activeProjectId == nil)
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
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                store.requirePro(
                    allowed: store.canCreateProject(),
                    context: .projectLimit
                ) {
                    dialogText = "Project \(state.visibleProjects.count + 1)"
                    isCreatingProject = true
                }
            }

            if !projectTemplates.isEmpty {
                Menu("New Project from Template") {
                    ForEach(projectTemplates) { template in
                        Button {
                            store.requirePro(
                                allowed: store.canCreateProject(),
                                context: .projectLimit
                            ) {
                                pendingTemplate = template
                                dialogText = template.name
                                isCreatingFromTemplate = true
                            }
                        } label: {
                            Label {
                                Text(template.name)
                            } icon: {
                                if let nsImage = template.previewImage {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                }
                            }
                        }
                    }
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
        Button("Export to Folder...") {
            exportScreenshotsAs()
        }

        Button("Export rows as continuous images") {
            exportRowImages()
        }
        .disabled(state.rows.isEmpty)

        if hasLastExportDestination {
            Button("Open Export Folder") {
                openLastExportFolder()
            }

            Divider()

            Text("Current export folder: \(lastExportFolderName)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var hasLastExportDestination: Bool {
        !lastExportFolderBookmark.isEmpty
    }

    private var lastExportFolderName: String {
        ExportFolderService.folderName(for: lastExportFolderPath)
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
        if let row = currentExportRow {
            return "Fit \(row.label.isEmpty ? "selected row" : row.label) to the editor"
        }
        return "Fit the selected row to the editor"
    }

    private var currentExportRow: ScreenshotRow? {
        if let selectedRowId = state.selectedRowId {
            return state.rows.first(where: { $0.id == selectedRowId })
        }
        return state.rows.first
    }

    private func fitZoomToWindow() {
        guard let row = currentExportRow, editorViewportHeight > 0 else { return }
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

    private func exportRowImages() {
        guard !state.rows.isEmpty else { return }
        guard let baseURL = chooseExportDestination() else { return }

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0
        exportTotal = state.rows.count

        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let rowsDir = ExportService.uniqueFolder(named: "rows", in: baseURL)
                try FileManager.default.createDirectory(at: rowsDir, withIntermediateDirectories: true)

                let localeCode = state.localeState.activeLocaleCode
                var imageCache: [String: NSImage] = [:]
                for (index, row) in state.rows.enumerated() {
                    try Task.checkCancellation()
                    let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                    let rowImages = state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    let image = ExportService.renderRowImage(
                        row: row,
                        screenshotImages: rowImages,
                        localeCode: localeCode,
                        localeState: state.localeState
                    )
                    guard let data = ExportService.encodeImage(image, format: .png) else {
                        exportError = "Failed to render row \(index + 1)"
                        return
                    }
                    let paddedIndex = String(format: "%02d", index + 1)
                    let fileName = row.label.isEmpty ? "\(paddedIndex).png" : "\(paddedIndex)_\(row.label).png"
                    try data.write(to: rowsDir.appendingPathComponent(fileName))
                    exportProgress = index + 1
                }

                if openExportFolderOnSuccess {
                    NSWorkspace.shared.activateFileViewerSelecting([rowsDir])
                }
                showExportSuccess()
            } catch is CancellationError {
                // User cancelled — no error to show
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func showExportSuccess() {
        exportSuccessTimer?.cancel()
        exportSuccess = true
        let timer = DispatchWorkItem { exportSuccess = false }
        exportSuccessTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)
    }

    private func chooseExportDestination() -> URL? {
        ExportFolderService.chooseFolder()
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

        exportTask = Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isExporting = false
                exportTask = nil
            }
            do {
                let projectName = state.activeProject?.name ?? ""
                let format = ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png
                var imageCache: [String: NSImage] = [:]
                let destinationFolderURL = try await ExportService.exportAll(
                    rows: state.rows,
                    projectName: projectName,
                    to: url,
                    format: format,
                    imageProvider: { [state] row, localeCode in
                        let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                        return state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    },
                    localeState: state.localeState,
                    availableFontFamilies: state.availableFontFamilySet,
                    onProgress: { completed in
                        exportProgress = completed
                    }
                )
                showExportSuccess()
                if openExportFolderOnSuccess {
                    NSWorkspace.shared.activateFileViewerSelecting([destinationFolderURL])
                }
            } catch is CancellationError {
                // User cancelled — no error to show
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private func lastExportFolderURL() -> URL? {
        guard let result = ExportFolderService.resolveBookmark(lastExportFolderBookmark) else {
            if !lastExportFolderBookmark.isEmpty {
                lastExportFolderBookmark = Data()
            }
            return nil
        }
        if let refreshed = result.refreshedBookmark {
            lastExportFolderBookmark = refreshed
        }
        return result.url
    }

    private func saveLastExportFolder(_ url: URL) {
        guard let result = ExportFolderService.saveBookmark(for: url) else {
            exportError = "Failed to remember export folder"
            return
        }
        lastExportFolderBookmark = result.bookmark
        lastExportFolderPath = result.path
    }

    private func openLastExportFolder() {
        guard let url = lastExportFolderURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @ViewBuilder
    private var paywallSheet: some View {
        if let configurationIssue = store.configurationIssue {
            VStack(alignment: .leading, spacing: 16) {
                Label("RevenueCat isn’t configured", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(configurationIssue)
                    .foregroundStyle(.secondary)

                Button("Close") {
                    store.dismissPaywall()
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(minWidth: 520, minHeight: 240)
            .padding(24)
        } else {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { store.handlePurchaseOrRestore($0) }
                .onRestoreCompleted { store.handlePurchaseOrRestore($0) }
                .onPurchaseFailure { store.handlePurchaseFailure($0) }
                .onRestoreFailure { store.handleRestoreFailure($0) }
                .onRequestedDismissal { store.dismissPaywall() }
                .frame(minWidth: 520, idealWidth: 560, maxWidth: 620, minHeight: 560, idealHeight: 620)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(StoreService())
}
