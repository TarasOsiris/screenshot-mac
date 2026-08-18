import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@Observable
final class AppState {
    static let maxProjectNameLength = 100
    static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]
    nonisolated static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

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
    @ObservationIgnored private(set) var endActiveInlineTextEdit: (() -> Void)?
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
    /// Interactive onboarding-tour runtime state + flow (see `OnboardingCoachController`).
    let coach = OnboardingCoachController()
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
    /// Canvas "scroll into view" request signals (see `CanvasFocusController`).
    let canvasFocus = CanvasFocusController()
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

    /// Every debounced/throttled editing burst: continuous shape/row edits, arrow-key nudge,
    /// base-text and translation typing. See `EditCoalescingCoordinator`.
    @ObservationIgnored let edits = EditCoalescingCoordinator()

    @ObservationIgnored nonisolated(unsafe) var arrowKeyMonitor: Any?
    @ObservationIgnored var zoomPersistTask: DispatchWorkItem?

    /// The shape targeted by an in-flight continuous edit (nil when idle).
    var continuousEditShapeId: UUID? { edits.shapeEdit.activeId }
    /// The row targeted by an in-flight continuous row edit (nil when idle).
    var continuousRowEditId: UUID? { edits.rowEdit.activeId }

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

    /// nil when no project is open. `activeProjectDataModifiedAt` wins because it tracks the last
    /// write of the row data itself; the project record's own timestamp is the fallback.
    var documentStamp: DocumentStamp? {
        guard let activeProjectId else { return nil }
        return DocumentStamp(
            projectId: activeProjectId,
            modifiedAt: activeProjectDataModifiedAt ?? activeProject?.modifiedAt
        )
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
        coach.app = self

        let lastZoom = UserDefaults.standard.double(forKey: "lastZoomLevel")
        if lastZoom > 0 {
            zoomLevel = lastZoom
        } else {
            let defaultZoom = UserDefaults.standard.double(forKey: "defaultZoomLevel")
            if defaultZoom > 0 { zoomLevel = defaultZoom }
        }

        // Tag before the first load, not after: a decode failure during `load()` is the one
        // report where "was this an iCloud read?" decides whether it's a sync bug or disk rot.
        CrashReportingService.setTag(PersistenceService.isUsingICloud ? "icloud" : "local", for: "storage")

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
                Task { @MainActor [weak self] in
                    self?.flushPendingSavesSynchronously()
                }
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
            Task { @MainActor [weak self] in
                self?.refreshTranslationsIfCatalogChanged()
            }
        }
        #endif
    }

    /// Flushes any in-flight continuous edits and pending debounced save so closing
    /// the main window (which terminates the app) doesn't drop unsaved changes.
    func flushPendingSavesSynchronously() {
        CrashReportingService.breadcrumb(.persistence, "Flushing pending saves", data: ["rows": rows.count])
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
            case PlatformKeyCode.LeftArrow:  self.nudgeSelectedShapes(dx: -step, dy: 0); return nil
            case PlatformKeyCode.RightArrow: self.nudgeSelectedShapes(dx: step, dy: 0); return nil
            case PlatformKeyCode.UpArrow:    self.nudgeSelectedShapes(dx: 0, dy: -step); return nil
            case PlatformKeyCode.DownArrow:  self.nudgeSelectedShapes(dx: 0, dy: step); return nil
            case PlatformKeyCode.Delete, PlatformKeyCode.ForwardDelete: self.deleteSelectedShape(); return nil
            default: return event
            }
        }
        #endif
    }

    // Undo/redo lives in AppState+Undo.swift; this flag is a stored property, which an
    // extension can't declare, and is internal so that file can read it.

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
