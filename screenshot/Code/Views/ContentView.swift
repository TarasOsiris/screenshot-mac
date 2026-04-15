import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(StoreService.self) private var store
    @Environment(\.openWindow) private var openWindow
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
    @State private var isRenamingProject = false
    @State private var dialogText = ""
    @State private var isDeletingProject = false
    @State private var isDuplicatingProject = false
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
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    editorViewportHeight = newValue
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
        #if DEBUG
        .overlay {
            if state.isEditingText,
               let selectionState = state.richTextSelectionState,
               let anchor = state.richTextFormatBarAnchor,
               let controller = state.richTextFormatController {
                GeometryReader { proxy in
                    let localPoint = proxy.frame(in: .global).origin
                    let barHalfW = RichTextFormatBarMetrics.width / 2
                    let barHalfH = RichTextFormatBarMetrics.height / 2
                    let rawX = anchor.x - localPoint.x
                    let rawY = anchor.y - localPoint.y - barHalfH
                    let inset = RichTextFormatBarMetrics.edgeInset
                    let clampedX = min(max(barHalfW + inset, rawX), proxy.size.width - barHalfW - inset)
                    let clampedY = min(max(barHalfH + inset, rawY), proxy.size.height - barHalfH - inset)
                    RichTextFormatBar(
                        selectionState: selectionState,
                        onApplyFormat: { action in
                            controller.applyAction(action)
                        }
                    )
                    .frame(width: RichTextFormatBarMetrics.width, height: RichTextFormatBarMetrics.height)
                    .position(x: clampedX, y: clampedY)
                }
                .zIndex(999)
            }
        }
        #endif
        .overlay {
            if !state.localeState.isBaseLocale {
                Rectangle()
                    .strokeBorder(Color.localeWarning.opacity(0.5), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isExporting {
                ExportProgressOverlay(
                    progress: exportProgress,
                    total: exportTotal,
                    onCancel: { exportTask?.cancel() }
                )
            }
        }
        .overlay {
            if !isExporting && (state.isOpeningProject || state.isLoadingImages) {
                ProjectLoadingOverlay(message: state.isOpeningProject ? "Opening Project…" : "Loading Images…")
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
        .alert("Duplicate Project", isPresented: $isDuplicatingProject) {
            TextField("Project name", text: $dialogText.limited(to: 100))
            Button("Duplicate") {
                if let id = state.activeProjectId {
                    state.duplicateProject(id, name: dialogText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: Binding(get: { store.showPaywall }, set: { _ in store.dismissPaywall() })) {
            PaywallSheetContent(store: store)
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
                // Defer to next tick so menu dismisses before alert presents
                Task { @MainActor in
                    dialogText = state.activeProject?.name ?? ""
                    isRenamingProject = true
                }
            }
            .disabled(state.activeProjectId == nil)

            Button("Duplicate Project...") {
                store.requirePro(
                    allowed: store.canCreateProject(),
                    context: .projectLimit
                ) {
                    Task { @MainActor in
                        dialogText = (state.activeProject?.name ?? "") + " Copy"
                        isDuplicatingProject = true
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

    private var projectSwitcherToolbarMenu: some View {
        Menu {
            projectMenuContent
        } label: {
            projectMenuLabel
        }
        .menuStyle(.button)
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

    private var inspectorToggleButton: some View {
        Button {
            isInspectorPresented.toggle()
        } label: {
            Label("Inspector", systemImage: "sidebar.trailing")
        }
        .help(isInspectorPresented ? "Hide inspector" : "Show inspector")
    }

    private var exportControlGroup: some View {
        ContentExportControl(
            isExporting: isExporting,
            exportSuccess: exportSuccess,
            buttonText: exportButtonText,
            helpText: exportHelpText,
            isDisabled: isExporting || state.rows.isEmpty,
            onExport: { exportScreenshots() }
        ) {
            exportMenuContent
        }
    }

    @ViewBuilder
    private var exportMenuContent: some View {
        Button("Export All Screenshots to Folder...") {
            exportScreenshotsAs()
        }

        Menu("Export Rows") {
            Button("Continuous") {
                exportRowImages()
            }
            Button("Showcase") {
                exportShowcaseImages()
            }
        }
        .disabled(state.rows.isEmpty)

        if state.localeState.locales.count > 1 {
            Menu("Export Locale") {
                ForEach(state.localeState.locales) { locale in
                    Button(locale.flagLabel) {
                        exportScreenshots(localeFilter: locale.code)
                    }
                }
            }
            .disabled(state.rows.isEmpty)
        }

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

    private func exportScreenshots(localeFilter: String? = nil) {
        if let savedURL = lastExportFolderURL() {
            exportScreenshots(to: savedURL, localeFilter: localeFilter)
        } else {
            exportScreenshotsAs(localeFilter: localeFilter)
        }
    }

    private func exportScreenshotsAs(localeFilter: String? = nil) {
        guard let url = chooseExportDestination() else { return }
        saveLastExportFolder(url)
        exportScreenshots(to: url, localeFilter: localeFilter)
    }

    private func exportRowImages() {
        exportRowLevel(folderName: "rows") { row, images, locale, localeState in
            ExportService.renderRowImage(row: row, screenshotImages: images, localeCode: locale, localeState: localeState)
        }
    }

    private func exportShowcaseImages() {
        exportRowLevel(folderName: "showcase") { row, images, locale, localeState in
            ExportService.renderShowcaseRowImage(row: row, screenshotImages: images, localeCode: locale, localeState: localeState)
        }
    }

    private func exportRowLevel(
        folderName: String,
        render: @MainActor @escaping (ScreenshotRow, [String: NSImage], String?, LocaleState) -> NSImage
    ) {
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
                let destDir = ExportService.uniqueFolder(named: folderName, in: baseURL)
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

                let localeCode = state.localeState.activeLocaleCode
                var imageCache: [String: NSImage] = [:]
                for (index, row) in state.rows.enumerated() {
                    try Task.checkCancellation()
                    let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                    let rowImages = state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    let image = render(row, rowImages, localeCode, state.localeState)
                    guard let data = ExportService.encodeImage(image, format: .png) else {
                        exportError = "Failed to render row \(index + 1)"
                        return
                    }
                    let paddedIndex = String(format: "%02d", index + 1)
                    let fileName = row.label.isEmpty ? "\(paddedIndex).png" : "\(paddedIndex)_\(row.label).png"
                    try data.write(to: destDir.appendingPathComponent(fileName))
                    exportProgress = index + 1
                    await Task.yield()
                }

                if openExportFolderOnSuccess {
                    NSWorkspace.shared.activateFileViewerSelecting([destDir])
                }
                showExportSuccess()
            } catch is CancellationError {
                // User cancelled
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

    private func exportScreenshots(to url: URL, localeFilter: String? = nil) {
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

        let localeCount = localeFilter == nil ? max(1, state.localeState.locales.count) : 1
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
                    localeFilter: localeFilter,
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

}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(StoreService())
}
