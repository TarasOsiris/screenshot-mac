import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

@Observable
final class AppState {
    static let maxProjectNameLength = 100
    static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    var projects: [Project] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var localeState: LocaleState = .default
    var selectedRowId: UUID?
    var selectedShapeIds: Set<UUID> = []
    /// The canvas's in-progress inline text edit. See InlineTextEditSession.
    let textEdit: InlineTextEditSession

    /// Editor zoom. Not document state — see ZoomController.
    let zoom = ZoomController()
    /// Preview mode and the iPad view mode. Session-only — see EditorViewModeController.
    let viewMode: EditorViewModeController

    @ObservationIgnored var canvasMouseModelPosition: CGPoint?
    @ObservationIgnored var visibleCanvasModelCenter: CGPoint?
    @ObservationIgnored var justAddedShapeId: UUID?
    @ObservationIgnored var templateMoveContinuation: TemplateMoveContinuation?
    /// View-to-view signals for the locale menu. See LocaleMenuCoordinator.
    let localeMenu = LocaleMenuCoordinator()
    /// Interactive onboarding-tour runtime state + flow (see `OnboardingCoachController`).
    let coach = OnboardingCoachController()
    var screenshotImages: [String: NSImage] = [:]
    /// User-imported fonts. See CustomFontLibrary.
    let fonts: CustomFontLibrary

    /// `RowRenderSource` conformance — the renderers ask the document, and it forwards.
    var availableFontFamilySet: Set<String> { fonts.availableFamilySet }

    var customFonts: [String: CustomFont] { fonts.customFonts }

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

    @ObservationIgnored var imageLoadTask: Task<Void, Never>?
    @ObservationIgnored var projectOpenTask: Task<Void, Never>?
    /// Serializes off-main iCloud reloads so overlapping remote changes don't race on the
    /// tombstone merge / own-write bookkeeping.
    @ObservationIgnored var reloadTask: Task<Void, Never>?
    var isOpeningProject = false
    /// False until the first `load()` completes. Lets the UI show a loading state instead of
    /// the empty "no projects" screen while an iCloud-deferred load is still pending.
    var hasCompletedInitialLoad = false
    /// Mirror of the iCloud monitor's upload/download progress. Drives the "Downloading from
    /// iCloud…" UI; injected into the environment so views needing only this don't take AppState.
    let iCloudStatus = ICloudSyncStatusModel()

    /// Every debounced/throttled editing burst: continuous shape/row edits, arrow-key nudge,
    /// base-text and translation typing. See `EditCoalescingCoordinator`.
    @ObservationIgnored let edits = EditCoalescingCoordinator()

    /// Arrow-key nudge / Delete. See CanvasKeyCommandMonitor.
    @ObservationIgnored let keyCommands = CanvasKeyCommandMonitor()

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

    init(fonts: CustomFontLibrary = CustomFontLibrary()) {
        let textEdit = InlineTextEditSession()
        self.fonts = fonts
        self.textEdit = textEdit
        self.viewMode = EditorViewModeController(textEdit: textEdit)
        coach.app = self
        viewMode.deselectAll = { [weak self] in self?.deselectAll() }

        zoom.restorePersistedLevel()

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
                // Must run before the observer returns — a Task deferred to a later runloop
                // turn may never be scheduled before process teardown, losing the last edit.
                MainActor.assumeIsolated {
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
        zoom.flushPendingPersist()
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

    // macOS virtual key codes

    /// Every handler captures `self` weakly: `keyCommands` is owned by this object, so a strong
    /// capture is a cycle nothing breaks.
    private func installArrowKeyMonitor() {
        keyCommands.install(.init(
            hasSelection: { [weak self] in self?.hasSelection ?? false },
            isEditingText: { [weak self] in self?.textEdit.isActive ?? false },
            nudge: { [weak self] dx, dy in self?.nudgeSelectedShapes(dx: dx, dy: dy) },
            delete: { [weak self] in self?.deleteSelectedShape() }
        ))
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
        let defaultSize = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultScreenshotSize) ?? AppSettingsKeys.Default.defaultScreenshotSize
        let parsedSize = parseSizeString(defaultSize)
        let w: CGFloat = width ?? parsedSize?.width ?? 1242
        let h: CGFloat = height ?? parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: AppSettingsKeys.defaultTemplateCount)
        let resolvedTemplateCount = templateCount ?? (storedTemplateCount > 0 ? storedTemplateCount : AppSettingsKeys.Default.defaultTemplateCount)
        let templates = (0..<resolvedTemplateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let deviceCategoryRaw = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultDeviceCategory) ?? AppSettingsKeys.Default.defaultDeviceCategory
        let resolvedDeviceCategory = defaultDeviceCategory ?? DeviceCategory(rawValue: deviceCategoryRaw)
        let storedDeviceFrameId = UserDefaults.standard.string(forKey: AppSettingsKeys.defaultDeviceFrameId).flatMap { $0.isEmpty ? nil : $0 }
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
