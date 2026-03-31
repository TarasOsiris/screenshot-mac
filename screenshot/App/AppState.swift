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
        var families = Set(NSFontManager.shared.availableFontFamilies)
        // Process-registered fonts (via CTFontManager) may not appear in
        // NSFontManager.availableFontFamilies. Include them explicitly.
        for familyName in customFonts.values {
            families.insert(familyName)
        }
        availableFontFamilySet = families
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

    @ObservationIgnored var saveTask: DispatchWorkItem?
    @ObservationIgnored var imageLoadTask: Task<Void, Never>?
    @ObservationIgnored var projectOpenTask: Task<Void, Never>?
    var isLoadingImages = false
    var isOpeningProject = false

    // Debounce state for undo grouping
    @ObservationIgnored var translationUndoTask: DispatchWorkItem?
    @ObservationIgnored var translationBaseLocaleState: LocaleState?
    @ObservationIgnored var baseTextUndoTask: DispatchWorkItem?
    @ObservationIgnored var baseTextBaseRow: ScreenshotRow?
    @ObservationIgnored var nudgeUndoTask: DispatchWorkItem?
    @ObservationIgnored var nudgeBaseRow: ScreenshotRow?
    @ObservationIgnored var continuousEditUndoTask: DispatchWorkItem?
    @ObservationIgnored var continuousEditBaseRow: ScreenshotRow?
    @ObservationIgnored var continuousEditBaseLocaleState: LocaleState?
    @ObservationIgnored var continuousEditLastApply: CFAbsoluteTime = 0
    @ObservationIgnored var continuousEditPending: CanvasShapeModel?
    @ObservationIgnored var continuousEditFlushTask: DispatchWorkItem?
    @ObservationIgnored var zoomPersistTask: DispatchWorkItem?

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
    var textStyleClipboard: TextStyle?

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

    /// Full snapshot undo — captures ALL rows + localeState. Use for multi-row operations
    /// (add/delete/move row, etc.) where the row count or order changes.
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

    /// Row-scoped undo — captures only one row + localeState. Use for single-row mutations
    /// (shape edits, template changes, row property edits) where row count/order doesn't change.
    func registerUndoForRow(at rowIndex: Int, _ actionName: String) {
        registerUndoForRowWithBase(actionName, baseRow: rows[rowIndex], baseLocaleState: localeState)
    }

    /// Row-scoped undo with a pre-captured base row. Looks up the row by ID on undo/redo,
    /// so it's safe even if row indices shift (though callers should only use this when row count is stable).
    func registerUndoForRowWithBase(_ actionName: String, baseRow: ScreenshotRow, baseLocaleState: LocaleState? = nil) {
        guard let undoManager else { return }
        let savedLocaleState = baseLocaleState ?? localeState
        let savedRowId = baseRow.id
        undoManager.registerUndo(withTarget: self) { target in
            guard let currentIdx = target.rows.firstIndex(where: { $0.id == savedRowId }) else { return }
            let redoRow = target.rows[currentIdx]
            let redoLocaleState = target.localeState
            target.undoManager?.registerUndo(withTarget: target) { t in
                guard let idx = t.rows.firstIndex(where: { $0.id == savedRowId }) else { return }
                t.rows[idx] = redoRow
                t.localeState = redoLocaleState
                t.normalizeSelection()
                t.scheduleSave()
                t.undoManager?.setActionName(actionName)
            }
            target.rows[currentIdx] = baseRow
            target.localeState = savedLocaleState
            target.normalizeSelection()
            target.scheduleSave()
            target.undoManager?.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Helpers

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
        nudgeBaseRow = nil
        baseTextUndoTask?.cancel()
        baseTextUndoTask = nil
        baseTextBaseRow = nil
        continuousEditUndoTask?.cancel()
        continuousEditUndoTask = nil
        continuousEditBaseRow = nil
        continuousEditBaseLocaleState = nil
        continuousEditFlushTask?.cancel()
        continuousEditFlushTask = nil
        continuousEditPending = nil
    }

    func makeDefaultRow(id: UUID = UUID(), label: String? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> ScreenshotRow {
        makeDefaultRow(
            id: id,
            label: label,
            width: width,
            height: height,
            templateCount: nil,
            defaultDeviceCategory: nil,
            defaultDeviceFrameId: nil
        )
    }

    func makeDefaultRow(
        id: UUID = UUID(),
        label: String? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        templateCount: Int?,
        defaultDeviceCategory: DeviceCategory?,
        defaultDeviceFrameId: String?
    ) -> ScreenshotRow {
        let defaultSize = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
        let parsedSize = parseSizeString(defaultSize)
        let w: CGFloat = width ?? parsedSize?.width ?? 1242
        let h: CGFloat = height ?? parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        let resolvedTemplateCount = templateCount ?? (storedTemplateCount > 0 ? storedTemplateCount : 3)
        let templates = (0..<resolvedTemplateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let deviceCategoryRaw = UserDefaults.standard.string(forKey: "defaultDeviceCategory") ?? "iphone"
        let resolvedDeviceCategory = defaultDeviceCategory ?? DeviceCategory(rawValue: deviceCategoryRaw)
        let storedDeviceFrameId = UserDefaults.standard.string(forKey: "defaultDeviceFrameId").flatMap { $0.isEmpty ? nil : $0 }
        let resolvedDeviceFrame = defaultDeviceFrameId ?? storedDeviceFrameId
        let resolvedFrame = resolvedDeviceFrame.flatMap { DeviceFrameCatalog.frame(for: $0) }

        var shapes: [CanvasShapeModel] = []
        if let resolvedDeviceCategory {
            shapes = (0..<resolvedTemplateCount).map { index in
                var device = CanvasShapeModel.defaultDevice(
                    centerX: CGFloat(index) * w + w / 2,
                    centerY: h / 2,
                    templateHeight: h,
                    category: resolvedDeviceCategory
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
            defaultDeviceCategory: resolvedDeviceCategory,
            defaultDeviceFrameId: resolvedDeviceFrame,
            shapes: shapes,
            isLabelManuallySet: label != nil
        )
    }
}
