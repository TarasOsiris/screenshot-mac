import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    static let maxProjectNameLength = 100
    static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]
    static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    var projects: [Project] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var localeState: LocaleState = .default
    var selectedRowId: UUID?
    var selectedShapeIds: Set<UUID> = []
    var isEditingText = false
    var zoomLevel: CGFloat = 1.0
    @ObservationIgnored var canvasMouseModelPosition: CGPoint?
    @ObservationIgnored var visibleCanvasModelCenter: CGPoint?
    @ObservationIgnored var justAddedShapeId: UUID?
    var pendingTranslateShapeId: UUID?
    var screenshotImages: [String: NSImage] = [:]
    var customFonts: [String: String] = [:]  // fileName → familyName
    /// Cached set of all available font family names for O(1) lookups during rendering.
    @ObservationIgnored private(set) var availableFontFamilySet: Set<String> = Set(NSFontManager.shared.availableFontFamilies)

    func refreshAvailableFontFamilies() {
        availableFontFamilySet = Set(NSFontManager.shared.availableFontFamilies)
    }
    var undoManager: UndoManager?
    var saveError: String?
    var canvasFocusRowId: UUID?
    var canvasFocusRequestNonce = 0
    var canvasFocusAnimated = true
    var focusShapeId: UUID?
    var focusRequestNonce = 0
    @ObservationIgnored var iCloudMonitor: ICloudMonitor?
    /// Tracks when the active project data was last saved/loaded, for merge decisions.
    @ObservationIgnored var activeProjectDataModifiedAt: Date?

    var saveTask: DispatchWorkItem?
    @ObservationIgnored var imageLoadTask: Task<Void, Never>?
    var isLoadingImages = false

    // Debounce state for undo grouping
    var translationUndoTask: DispatchWorkItem?
    var translationBaseLocaleState: LocaleState?
    var baseTextUndoTask: DispatchWorkItem?
    var baseTextBaseRows: [ScreenshotRow]?
    var nudgeUndoTask: DispatchWorkItem?
    var nudgeBaseRows: [ScreenshotRow]?
    var zoomPersistTask: DispatchWorkItem?

    /// Single-selection convenience: returns the sole selected shape ID, or nil.
    var selectedShapeId: UUID? {
        get { selectedShapeIds.count == 1 ? selectedShapeIds.first : nil }
        set {
            if let id = newValue {
                selectedShapeIds = [id]
            } else {
                selectedShapeIds = []
            }
        }
    }

    var hasSelection: Bool { !selectedShapeIds.isEmpty }

    // Clipboard
    var clipboard: [CanvasShapeModel] = []
    var clipboardPasteboardChangeCount: Int = 0

    var activeProject: Project? {
        visibleProjects.first { $0.id == activeProjectId }
    }

    var visibleProjects: [Project] {
        projects.filter { !$0.isDeleted }
    }

    var selectedRow: ScreenshotRow? {
        rows.first { $0.id == selectedRowId }
    }

    var selectedRowIndex: Int? {
        rows.firstIndex { $0.id == selectedRowId }
    }

    func rowIndex(for rowId: UUID) -> Int? {
        rows.firstIndex { $0.id == rowId }
    }

    init() {
        let lastZoom = UserDefaults.standard.double(forKey: "lastZoomLevel")
        if lastZoom > 0 {
            zoomLevel = lastZoom
        } else {
            let defaultZoom = UserDefaults.standard.double(forKey: "defaultZoomLevel")
            if defaultZoom > 0 { zoomLevel = defaultZoom }
        }

        // If iCloud is enabled (and we're not in test mode), defer loading until
        // the container is resolved — setupICloudIfNeeded will call load() after.
        let iCloudPending = !PersistenceService.hasDataDirOverride && ICloudSyncService.shared.isEnabled
        if !iCloudPending {
            PersistenceService.ensureDirectories()
            load()
        }

        if !PersistenceService.hasDataDirOverride {
            setupICloudIfNeeded()
        }
    }

    // MARK: - Undo

    func registerUndo(_ actionName: String) {
        registerUndoWithBase(actionName, base: rows, baseLocaleState: localeState)
    }

    func registerUndoWithBase(_ actionName: String, base: [ScreenshotRow], baseLocaleState: LocaleState? = nil) {
        guard let undoManager else { return }
        let savedLocaleState = baseLocaleState ?? localeState
        undoManager.registerUndo(withTarget: self) { target in
            let redoRows = target.rows
            let redoLocaleState = target.localeState
            target.undoManager?.registerUndo(withTarget: target) { t in
                t.rows = redoRows
                t.localeState = redoLocaleState
                t.normalizeSelection()
                t.scheduleSave()
                t.undoManager?.setActionName(actionName)
            }
            target.rows = base
            target.localeState = savedLocaleState
            target.normalizeSelection()
            target.scheduleSave()
            target.undoManager?.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Zoom

    func setZoomLevel(_ level: CGFloat, animated: Bool = true) {
        let clamped = min(ZoomConstants.max, max(ZoomConstants.min, level))
        guard clamped != zoomLevel else { return }
        if animated {
            withAnimation(.smooth(duration: 0.3)) {
                zoomLevel = clamped
            }
        } else {
            zoomLevel = clamped
        }
        zoomPersistTask?.cancel()
        let task = DispatchWorkItem {
            UserDefaults.standard.set(clamped, forKey: "lastZoomLevel")
        }
        zoomPersistTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    func zoomIn() {
        setZoomLevel(zoomLevel + ZoomConstants.step)
    }

    func zoomOut() {
        setZoomLevel(zoomLevel - ZoomConstants.step)
    }

    func resetZoom() {
        let defaultLevel = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        setZoomLevel(defaultLevel > 0 ? defaultLevel : 1.0)
        zoomPersistTask?.cancel()
        UserDefaults.standard.removeObject(forKey: "lastZoomLevel")
    }

    // MARK: - Selection

    func selectRow(_ id: UUID?) {
        guard let id else {
            deselectAll()
            return
        }
        guard rows.contains(where: { $0.id == id }) else { return }
        let rowChanged = selectedRowId != id
        selectedRowId = id
        selectedShapeIds = []
        if rowChanged {
            visibleCanvasModelCenter = nil
        }
    }

    func selectShape(_ shapeId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        selectedRowId = rowId
        selectedShapeIds = [shapeId]
    }

    func toggleShapeSelection(_ shapeId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        // Different row → switch row and select just this shape
        if selectedRowId != rowId {
            selectedRowId = rowId
            selectedShapeIds = [shapeId]
            visibleCanvasModelCenter = nil
            return
        }
        if isEditingText {
            isEditingText = false
        }
        if selectedShapeIds.contains(shapeId) {
            selectedShapeIds.remove(shapeId)
        } else {
            selectedShapeIds.insert(shapeId)
        }
    }

    func selectAllShapesInRow() {
        guard let rowIdx = selectedRowIndex else { return }
        selectedShapeIds = Set(rows[rowIdx].activeShapes.map(\.id))
    }

    func deselectAll() {
        selectedShapeIds = []
        selectedRowId = nil
        isEditingText = false
    }

    /// Scroll to center the selected shape(s) on screen.
    func focusOnSelection() {
        guard let rowId = selectedRowId,
              !selectedShapeIds.isEmpty else { return }
        guard rows.contains(where: { $0.id == rowId }) else { return }
        canvasFocusAnimated = false
        canvasFocusRowId = rowId
        canvasFocusRequestNonce += 1
        focusShapeId = selectedShapeIds.first
        focusRequestNonce += 1
    }

    // MARK: - Helpers

    func normalizeSelection() {
        if let selectedRowId, !rows.contains(where: { $0.id == selectedRowId }) {
            self.selectedRowId = rows.first?.id
        }

        if !selectedShapeIds.isEmpty {
            guard let rowIdx = selectedRowIndex else {
                selectedShapeIds = []
                isEditingText = false
                return
            }
            let existingIds = Set(rows[rowIdx].shapes.map(\.id))
            selectedShapeIds = selectedShapeIds.intersection(existingIds)
            if selectedShapeIds.isEmpty {
                isEditingText = false
            }
        }
    }

    func shapeLocation(for shapeId: UUID) -> (rowIndex: Int, shapeIndex: Int)? {
        for rowIndex in rows.indices {
            if let shapeIndex = rows[rowIndex].shapes.firstIndex(where: { $0.id == shapeId }) {
                return (rowIndex, shapeIndex)
            }
        }
        return nil
    }

    func allTextShapes() -> [CanvasShapeModel] {
        rows.flatMap { row in
            row.shapes.filter { $0.type == .text }
        }
    }

    func cancelPendingDebounceTasks() {
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil
        nudgeUndoTask?.cancel()
        nudgeUndoTask = nil
        nudgeBaseRows = nil
    }

    func makeDefaultRow(id: UUID = UUID(), label: String? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> ScreenshotRow {
        let defaultSize = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
        let parsedSize = parseSizeString(defaultSize)
        let w: CGFloat = width ?? parsedSize?.width ?? 1242
        let h: CGFloat = height ?? parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        let templateCount = storedTemplateCount > 0 ? storedTemplateCount : 3
        let templates = (0..<templateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let deviceCategoryRaw = UserDefaults.standard.string(forKey: "defaultDeviceCategory") ?? "iphone"
        let deviceCategory = DeviceCategory(rawValue: deviceCategoryRaw)
        let deviceFrameId = UserDefaults.standard.string(forKey: "defaultDeviceFrameId").flatMap { $0.isEmpty ? nil : $0 }
        let resolvedFrame = deviceFrameId.flatMap { DeviceFrameCatalog.frame(for: $0) }

        var shapes: [CanvasShapeModel] = []
        if let deviceCategory {
            shapes = (0..<templateCount).map { index in
                var device = CanvasShapeModel.defaultDevice(
                    centerX: CGFloat(index) * w + w / 2,
                    centerY: h / 2,
                    templateHeight: h,
                    category: deviceCategory
                )
                if let resolvedFrame {
                    device.deviceCategory = resolvedFrame.fallbackCategory
                    device.deviceFrameId = resolvedFrame.id
                    device.adjustToDeviceAspectRatio(centerX: CGFloat(index) * w + w / 2)
                }
                return device
            }
        }
        let resolvedLabel = label ?? presetLabel(forWidth: w, height: h)
        return ScreenshotRow(
            id: id,
            label: resolvedLabel,
            templates: templates,
            templateWidth: w,
            templateHeight: h,
            defaultDeviceCategory: deviceCategory,
            defaultDeviceFrameId: deviceFrameId,
            shapes: shapes,
            isLabelManuallySet: label != nil
        )
    }
}
