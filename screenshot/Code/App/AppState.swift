import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

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
    var isEditingText = false {
        didSet {
            if !isEditingText {
                richTextSelectionState = nil
                richTextFormatBarAnchor = nil
                richTextFormatController = nil
                // The inline commit registration is cleared by the editing view's keyed
                // teardown (onInlineTextEditChanged(nil)); clearing it unkeyed here would
                // wipe a newer editor's registration during an editor-to-editor handoff.
            }
        }
    }
    var richTextSelectionState: RichTextSelectionState?
    var richTextFormatBarAnchor: CGPoint?
    @ObservationIgnored var richTextFormatController: RichTextFormatController?
    /// Commits the editing `CanvasShapeView`'s in-progress inline text under the *current*
    /// locale; registered while editing, flushed by `commitAllPendingEdits` before locale switches.
    @ObservationIgnored private(set) var commitActiveInlineTextEdit: (() -> Void)?
    @ObservationIgnored private var endActiveInlineTextEdit: (() -> Void)?
    @ObservationIgnored private var inlineTextEditShapeId: UUID?

    /// Register the active inline text editor's commit closure, keyed by shape so a stale
    /// teardown from a previously-editing shape can't clear a newer editor's registration.
    func registerInlineTextCommit(for shapeId: UUID, endEditing: (() -> Void)? = nil, _ commit: @escaping () -> Void) {
        inlineTextEditShapeId = shapeId
        commitActiveInlineTextEdit = commit
        endActiveInlineTextEdit = endEditing
    }

    /// Clear the registered inline commit. With a `shapeId`, only clears if it still owns the
    /// registration (ignores a late clear from a shape that's already been superseded).
    func clearInlineTextCommit(for shapeId: UUID? = nil) {
        if let shapeId, inlineTextEditShapeId != shapeId { return }
        inlineTextEditShapeId = nil
        commitActiveInlineTextEdit = nil
        endActiveInlineTextEdit = nil
    }
    var zoomLevel: CGFloat = 1.0
    /// Rows currently shown in preview mode. Session-only — not persisted.
    private(set) var previewingRows: Set<UUID> = []

    /// Flip the row's preview-mode state. Also drops `isEditingText` when
    /// entering preview so a stale text-editor focus doesn't survive into the
    /// non-interactive preview.
    func togglePreview(for rowId: UUID) {
        if previewingRows.contains(rowId) {
            previewingRows.remove(rowId)
        } else {
            previewingRows.insert(rowId)
            isEditingText = false
        }
    }

    /// Exit preview mode for a row. Idempotent.
    func exitPreview(for rowId: UUID) {
        previewingRows.remove(rowId)
    }

    /// Drop any preview-mode entries that don't refer to a row in `validIds`.
    /// Called when rows are replaced wholesale (project switch, iCloud reload).
    func reconcilePreviewingRows(against validIds: Set<UUID>) {
        previewingRows = previewingRows.intersection(validIds)
    }

    /// iOS-only editor view mode: shapes are inert, only panning + pinch-zoom work.
    /// Session-only, never persisted; always false on macOS.
    var isViewMode = false

    /// Toggle the editor view mode. Entering it clears any active text edit and
    /// selection so no editing chrome lingers over the non-interactive canvas.
    func setViewMode(_ on: Bool) {
        guard isViewMode != on else { return }
        isViewMode = on
        if on {
            isEditingText = false
            deselectAll()
        }
    }
    @ObservationIgnored var canvasMouseModelPosition: CGPoint?
    @ObservationIgnored var visibleCanvasModelCenter: CGPoint?
    @ObservationIgnored var justAddedShapeId: UUID?
    @ObservationIgnored var templateMoveContinuation: TemplateMoveContinuation?
    var pendingTranslateShapeId: UUID?
    var pendingFanOutTranslateShapeIds: Set<UUID>?
    var pendingLocaleMenuRequest: LocaleMenuRequest?
    /// Active step of the interactive onboarding tour. `nil` when no tour is in progress.
    var coachStep: OnboardingCoachStep?
    #if os(iOS)
    /// Set during the brief gap between coach marks (see `setCoachStep`) so anchor
    /// views can prepare — e.g. scroll the upcoming anchor into view — before the
    /// next popover presents.
    var coachPreparingStep: OnboardingCoachStep?
    @ObservationIgnored var coachTransitionTask: Task<Void, Never>?
    #endif
    /// When false, `endCoach()` skips persisting `onboardingCompleted`. Used by the debug
    /// "Run Coach Tour" command so it can be re-run without consuming the real flag.
    @ObservationIgnored var coachPersistsOnEnd: Bool = true
    /// Mirrors whether the Get Pro toolbar button is currently shown. The final coach
    /// step anchors on that button, so the tour skips it when Pro is already unlocked.
    @ObservationIgnored var coachProStepAvailable: Bool = true
    var screenshotImages: [String: NSImage] = [:]
    var customFonts: [String: CustomFont] = [:]  // fileName → CustomFont
    /// Family names referenced by any shape at some point in the current session. A font
    /// is only eligible for in-session cleanup once its family enters this set — otherwise
    /// a freshly imported font (or auto-imported sibling variant) would be deleted by the
    /// next debounced save before the user has a chance to apply it.
    @ObservationIgnored var everReferencedFontFamilies: Set<String> = []
    /// Includes both system family names and custom font display names so render-time
    /// `.contains(name)` checks succeed for style-qualified variants like
    /// "Playfair Display Italic".
    @ObservationIgnored private(set) var availableFontFamilySet: Set<String> = PlatformFonts.familyNameSet

    func refreshAvailableFontFamilies() {
        // Process-registered fonts (via CTFontManager) don't appear in the system family
        // list, so add both family and display names.
        PlatformFonts.invalidateFamilyNameCache()
        var families = PlatformFonts.familyNameSet
        let resourcesURL = activeProjectId.map { PersistenceService.resourcesDir($0) }
        var instances: [CustomFont] = []
        for font in customFonts.values {
            families.insert(font.familyName)
            families.insert(font.displayName)
            if let resourcesURL {
                instances.append(contentsOf: CustomFont.allInstances(at: resourcesURL.appendingPathComponent(font.fileName)))
            }
        }
        availableFontFamilySet = families
        CustomFontRegistry.update(with: customFonts, instances: instances)
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
    /// `translations.xcstrings` mod-date the active project last read or wrote, so an external
    /// (Xcode/translator) edit can be told apart from our own dual-write on re-activation.
    /// Reset on every project load via `applyProjectData`, so it always tracks the active project.
    @ObservationIgnored var lastSeenCatalogModified: Date?

    @ObservationIgnored var saveTask: DispatchWorkItem?
    /// Last time the autosave completion ran the full-document font-reference walk.
    @ObservationIgnored var lastFontCleanupAt: Date = .distantPast
    @ObservationIgnored var imageLoadTask: Task<Void, Never>?
    @ObservationIgnored var projectOpenTask: Task<Void, Never>?
    /// Serializes off-main iCloud reloads so overlapping remote changes don't race on the
    /// tombstone merge / own-write bookkeeping.
    @ObservationIgnored var reloadTask: Task<Void, Never>?
    var isLoadingImages = false
    var isOpeningProject = false
    var isFanOutTranslating = false
    /// False until the first `load()` completes. Lets the UI show a loading state instead of
    /// the empty "no projects" screen while an iCloud-deferred load is still pending.
    var hasCompletedInitialLoad = false
    /// Mirror of the iCloud monitor's upload/download progress, bridged here because
    /// `ICloudMonitor` isn't `@Observable`. Drives the "Downloading from iCloud…" UI.
    var iCloudSyncStatus: SyncStatus = .idle

    // Debounce state for undo grouping
    @ObservationIgnored var translationUndoTask: DispatchWorkItem?
    @ObservationIgnored var translationBaseLocaleState: LocaleState?
    @ObservationIgnored var baseTextUndoTask: DispatchWorkItem?
    @ObservationIgnored var baseTextBaseRow: ScreenshotRow?
    /// Whole-document base for a base-text edit that propagates across rows (a shared/reused string).
    @ObservationIgnored var baseTextBaseRows: [ScreenshotRow]?
    @ObservationIgnored var arrowKeyMonitor: Any?
    @ObservationIgnored var nudgeUndoTask: DispatchWorkItem?
    @ObservationIgnored var nudgeBaseRow: ScreenshotRow?
    @ObservationIgnored var nudgeActionName: String = "Move Shape"
    @ObservationIgnored var continuousEditUndoTask: DispatchWorkItem?
    @ObservationIgnored var continuousEditBaseRow: ScreenshotRow?
    @ObservationIgnored var continuousEditBaseLocaleState: LocaleState?
    @ObservationIgnored var continuousEditLastApply: CFAbsoluteTime = 0
    @ObservationIgnored var continuousEditPending: CanvasShapeModel?
    @ObservationIgnored var continuousEditFlushTask: DispatchWorkItem?
    @ObservationIgnored var continuousEditShapeId: UUID?
    // Row-level continuous edits (e.g. dragging gradient stops/angle/center or
    // background image sliders): capture undo once per burst, debounce a single
    // undo registration instead of one per drag tick.
    @ObservationIgnored var continuousRowEditUndoTask: DispatchWorkItem?
    @ObservationIgnored var continuousRowEditBaseRow: ScreenshotRow?
    @ObservationIgnored var continuousRowEditBaseLocaleState: LocaleState?
    @ObservationIgnored var continuousRowEditId: UUID?
    @ObservationIgnored var continuousRowEditActionName: String = "Edit Background"
    @ObservationIgnored var continuousRowEditLastApply: CFAbsoluteTime = 0
    @ObservationIgnored var continuousRowEditWorkingRow: ScreenshotRow?
    @ObservationIgnored var continuousRowEditHasPendingApply = false
    @ObservationIgnored var continuousRowEditFlushTask: DispatchWorkItem?
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

        installArrowKeyMonitor()

        // iOS does NOT reliably deliver willTerminate (suspended apps killed for memory, or
        // swiped from the app switcher, never fire it), so on iPad also persist whenever the
        // app leaves the foreground — otherwise the debounced save and any in-flight edit are
        // silently lost.
        #if os(macOS)
        let saveNotifications: [Notification.Name] = [NSApplication.willTerminateNotification]
        #else
        let saveNotifications: [Notification.Name] = [
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willResignActiveNotification,
            UIApplication.willTerminateNotification,
        ]
        #endif
        for name in saveNotifications {
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.flushPendingSavesSynchronously()
            }
        }

        // Pick up translation edits made in Xcode's String Catalog editor while we were
        // backgrounded. macOS-only: editing the `.xcstrings` is a desktop workflow.
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTranslationsIfCatalogChanged()
        }
        #endif
    }

    /// Flushes any in-flight continuous edits and pending debounced save so closing
    /// the main window (which terminates the app) doesn't drop unsaved changes.
    func flushPendingSavesSynchronously() {
        commitAllPendingEdits()
        flushPendingSaveTask()
        flushPendingZoomPersist()
    }

    /// If a debounced save is queued, cancel it and run `saveAll()` immediately.
    func flushPendingSaveTask() {
        // Drain in-flight async saves first: a write queued by saveAllAsync would
        // be lost at process exit, and the synchronous saveAll below must not
        // interleave with one mid-write.
        Self.saveQueue.sync {}
        guard saveTask != nil else { return }
        saveTask?.cancel()
        saveTask = nil
        saveAll()
    }

    deinit {
        #if os(macOS)
        if let monitor = arrowKeyMonitor { NSEvent.removeMonitor(monitor) }
        #endif
    }

    // macOS virtual key codes
    static let kVKLeftArrow: UInt16 = 0x7B
    static let kVKRightArrow: UInt16 = 0x7C
    static let kVKDownArrow: UInt16 = 0x7D
    static let kVKUpArrow: UInt16 = 0x7E
    static let kVKDelete: UInt16 = 0x33
    static let kVKForwardDelete: UInt16 = 0x75

    private func installArrowKeyMonitor() {
        // Arrow-key nudge and Delete use a global NSEvent monitor (macOS only) so they work
        // reliably without a focused first responder, while still passing through to text fields.
        // On iPad, these are deferred to on-screen controls.
        #if os(macOS)
        arrowKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if let responder = NSApp.keyWindow?.firstResponder,
               responder is NSTextView {
                return event
            }
            guard self.hasSelection, !self.isEditingText else { return event }
            let shift = event.modifierFlags.contains(.shift)
            let step: CGFloat = shift ? 10 : 1
            switch event.keyCode {
            case Self.kVKLeftArrow:  self.nudgeSelectedShapes(dx: -step, dy: 0); return nil
            case Self.kVKRightArrow: self.nudgeSelectedShapes(dx: step, dy: 0); return nil
            case Self.kVKUpArrow:    self.nudgeSelectedShapes(dx: 0, dy: -step); return nil
            case Self.kVKDownArrow:  self.nudgeSelectedShapes(dx: 0, dy: step); return nil
            case Self.kVKDelete, Self.kVKForwardDelete: self.deleteSelectedShape(); return nil
            default: return event
            }
        }
        #endif
    }

    // MARK: - Undo

    @ObservationIgnored private var isInUndoTransaction = false

    /// Wraps a document mutation so undo is captured automatically: snapshots the whole
    /// document before `body`, restores it on undo (re-registering redo), and schedules the
    /// save. A `body` that changes nothing registers no undo step. Nested `withUndo` calls
    /// join the outer transaction so a wrapped helper doesn't create a second step.
    func withUndo(_ actionName: String, _ body: () -> Void) {
        commitAllPendingEdits()
        if isInUndoTransaction { body(); return }
        isInUndoTransaction = true
        defer { isInUndoTransaction = false }

        let baseRows = rows
        let baseLocaleState = localeState
        body()
        guard rows != baseRows || localeState != baseLocaleState else { return }
        registerSnapshot(actionName, baseRows: baseRows, baseLocaleState: baseLocaleState)
        scheduleSave()
    }

    /// Registers a whole-document restore on the undo stack, re-registering its own inverse
    /// so redo cycles back to the post-edit state. Shared by `withUndo` and the continuous-edit
    /// commit path.
    private func registerSnapshot(_ actionName: String, baseRows: [ScreenshotRow], baseLocaleState: LocaleState) {
        guard let undoManager else { return }
        registeringUndoStep(on: undoManager) {
            undoManager.registerUndo(withTarget: self) { target in
                let redoRows = target.rows
                let redoLocaleState = target.localeState
                target.rows = baseRows
                target.localeState = baseLocaleState
                target.templateMoveContinuation = nil
                target.normalizeSelection()
                target.scheduleSave()
                target.registerSnapshot(actionName, baseRows: redoRows, baseLocaleState: redoLocaleState)
                target.undoManager?.setActionName(actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    /// `registerUndo` requires an open undo group. With the default `groupsByEvent`, the
    /// run loop opens one per event (and `undo()`/`redo()` open one while replaying), so a
    /// group is normally already active. But when none is — `groupsByEvent = false` with no
    /// run loop (unit tests), where macOS throws "must begin a group before registering undo" —
    /// open one around the registration. No-op whenever a group is already active, so
    /// production grouping is unchanged.
    private func registeringUndoStep(on undoManager: UndoManager, _ body: () -> Void) {
        let needsGroup = undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        body()
        if needsGroup { undoManager.endUndoGrouping() }
    }

    /// Full-snapshot undo with a pre-captured base — used by the debounced translation-edit
    /// path, which captures its base before the keystroke burst. Discrete mutations go through
    /// `withUndo` instead.
    func registerUndoWithBase(_ actionName: String, base: [ScreenshotRow], baseLocaleState: LocaleState? = nil) {
        registerSnapshot(actionName, baseRows: base, baseLocaleState: baseLocaleState ?? localeState)
    }

    /// Row-scoped undo with a pre-captured base row. Looks up the row by ID on undo/redo,
    /// so it's safe even if row indices shift (though callers should only use this when row count is stable).
    func registerUndoForRowWithBase(_ actionName: String, baseRow: ScreenshotRow, baseLocaleState: LocaleState? = nil) {
        registerRowSnapshot(actionName, rowId: baseRow.id, baseRow: baseRow, baseLocaleState: baseLocaleState ?? localeState)
    }

    /// Row-scoped counterpart to `registerSnapshot`: restores a single row by ID and
    /// re-registers its own inverse, so undo↔redo cycles indefinitely (the earlier
    /// two-closure form dropped the step after the first redo). If the row no longer
    /// exists the step is skipped — callers only use this when the row count is stable.
    private func registerRowSnapshot(_ actionName: String, rowId: UUID, baseRow: ScreenshotRow, baseLocaleState: LocaleState) {
        guard let undoManager else { return }
        registeringUndoStep(on: undoManager) {
            undoManager.registerUndo(withTarget: self) { target in
                guard let idx = target.rows.firstIndex(where: { $0.id == rowId }) else { return }
                let redoRow = target.rows[idx]
                let redoLocaleState = target.localeState
                target.rows[idx] = baseRow
                target.localeState = baseLocaleState
                target.templateMoveContinuation = nil
                target.normalizeSelection()
                target.scheduleSave()
                target.registerRowSnapshot(actionName, rowId: rowId, baseRow: redoRow, baseLocaleState: redoLocaleState)
                target.undoManager?.setActionName(actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    var canUndoDocumentAction: Bool {
        hasPendingUndoableEdit || (undoManager?.canUndo ?? false)
    }

    // A pending edit (continuous burst or debounced nudge/text) is the user's most recent
    // change: committing it (the flush inside redo/undoDocumentAction) registers a fresh undo
    // step, which clears the redo stack. So redo is unavailable while one is pending — the
    // inverse of canUndoDocumentAction.
    var canRedoDocumentAction: Bool {
        !hasPendingUndoableEdit && (undoManager?.canRedo ?? false)
    }

    func undoDocumentAction() {
        commitAllPendingEdits()
        undoManager?.undo()
    }

    func redoDocumentAction() {
        commitAllPendingEdits()
        guard undoManager?.canRedo == true else { return }
        undoManager?.redo()
    }

    /// True while any continuous burst or debounced (nudge/base-text/translation) edit is
    /// captured but not yet registered as an undo step.
    private var hasPendingUndoableEdit: Bool {
        hasPendingContinuousEdit
            || nudgeBaseRow != nil
            || baseTextBaseRow != nil
            || baseTextBaseRows != nil
            || translationBaseLocaleState != nil
    }

    /// Commits every pending continuous/debounced edit, registering each as its own undo
    /// step. Called at undo-stack boundaries (discrete `withUndo` actions, undo, redo) and
    /// when a different debounced interaction begins, so steps register in chronological
    /// order. Each finisher is a no-op when its own path has nothing captured.
    func commitAllPendingEdits() {
        // Flush the canvas's in-progress inline text edit first, then tell the still-mounted
        // editor to leave local edit mode so it can't recommit that draft after a locale switch.
        // Clear handlers before invoking to avoid re-entry via commitInlineText's withUndo.
        let inlineFlush = commitActiveInlineTextEdit
        let inlineEnd = endActiveInlineTextEdit
        clearInlineTextCommit()
        inlineFlush?()
        inlineEnd?()
        finishContinuousEditIfNeeded()
        finishNudgeIfNeeded()
        finishBaseTextEditIfNeeded()
        finishTranslationEditIfNeeded()
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
        clearInlineTextCommit()
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil
        nudgeUndoTask?.cancel()
        nudgeUndoTask = nil
        nudgeBaseRow = nil
        baseTextUndoTask?.cancel()
        baseTextUndoTask = nil
        baseTextBaseRow = nil
        baseTextBaseRows = nil
        continuousEditUndoTask?.cancel()
        continuousEditUndoTask = nil
        continuousEditFlushTask?.cancel()
        continuousEditFlushTask = nil
        continuousEditPending = nil
        resetContinuousEditState()
        continuousRowEditUndoTask?.cancel()
        continuousRowEditUndoTask = nil
        continuousRowEditFlushTask?.cancel()
        continuousRowEditFlushTask = nil
        continuousRowEditWorkingRow = nil
        continuousRowEditHasPendingApply = false
        continuousRowEditBaseRow = nil
        continuousRowEditBaseLocaleState = nil
        continuousRowEditId = nil
        continuousRowEditLastApply = 0
    }

    func resetContinuousEditState() {
        continuousEditBaseRow = nil
        continuousEditBaseLocaleState = nil
        continuousEditShapeId = nil
        continuousEditLastApply = 0
        // The debounced undo task nil-outs nothing on its own; clear it here so a settled
        // burst doesn't leave `hasPendingContinuousEdit` stuck true until the next flush.
        continuousEditUndoTask = nil
    }

    private var hasPendingContinuousEdit: Bool {
        continuousEditBaseRow != nil
            || continuousEditPending != nil
            || continuousEditUndoTask != nil
            || continuousEditFlushTask != nil
            || continuousRowEditBaseRow != nil
            || continuousRowEditWorkingRow != nil
            || continuousRowEditHasPendingApply
            || continuousRowEditUndoTask != nil
            || continuousRowEditFlushTask != nil
    }

    func finishContinuousEditIfNeeded() {
        finishContinuousRowEditIfNeeded()

        guard continuousEditBaseRow != nil
            || continuousEditPending != nil
            || continuousEditUndoTask != nil
            || continuousEditFlushTask != nil
        else { return }

        continuousEditUndoTask?.cancel()
        continuousEditUndoTask = nil
        flushPendingContinuousEdit()

        if let baseRow = continuousEditBaseRow {
            registerUndoForRowWithBase("Edit Shape", baseRow: baseRow, baseLocaleState: continuousEditBaseLocaleState)
        }

        resetContinuousEditState()
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
