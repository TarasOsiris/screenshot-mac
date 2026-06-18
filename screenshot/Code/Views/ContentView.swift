#if os(macOS)
import AppKit
#else
import UIKit
#endif
import StoreKit
import SwiftUI
import UniformTypeIdentifiers


struct ContentView: View {
    enum ShowcaseExportMode {
        case allRows
        case singleRow
    }

    struct ShowcasePresentation: Identifiable {
        let id = UUID()
        let mode: ShowcaseExportMode
        let candidateRows: [ScreenshotRow]
    }

    @Environment(AppState.self) var state
    @Environment(StoreService.self) var store
    #if os(iOS)
    /// Scroll room reserved under the canvas for the floating bottom chrome
    /// (shape-properties bar and, while editing text, the format bar above it).
    var floatingBottomChromeMargin: CGFloat {
        var margin: CGFloat = 0
        if state.hasSelection { margin += 72 }
        if state.isEditingText { margin += RichTextFormatBarMetrics.height + 16 }
        return margin
    }
    #endif
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private var isInspectorCompact: Bool { horizontalSizeClass == .compact }
    #endif
    // macOS-only: see AppRootView — \.openWindow must not be read on iPadOS.
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    #endif
    @Environment(\.undoManager) var undoManager
    @Environment(\.requestReview) var requestReview
    @AppStorage("exportFormat") var exportFormat = "png"
    @AppStorage("exportCustomSuffix") var exportCustomSuffix = ""
    @AppStorage("openExportFolderOnSuccess") var openExportFolderOnSuccess = true
    @AppStorage("confirmBeforeDeleting") var confirmBeforeDeleting = true
    @AppStorage("lastExportFolderBookmark") var lastExportFolderBookmark = Data()
    @AppStorage("lastExportFolderPath") var lastExportFolderPath = ""
    @AppStorage("projectSortOrder") var projectSortOrder = "creation"
    @AppStorage("reviewExportCount") var reviewExportCount = 0
    @AppStorage("reviewLastPromptedVersion") var reviewLastPromptedVersion = ""
    @AppStorage("reviewFirstExportDate") var reviewFirstExportDate: Double = 0
    @AppStorage("reviewLastPromptDate") var reviewLastPromptDate: Double = 0
    @AppStorage("inspectorPresented") var isInspectorPresented = true
    #if os(iOS)
    @State private var inspectorSheetDetent: PresentationDetent = .large
    #endif
    @State var isExporting = false
    @State var exportSuccess = false
    @State var exportSuccessTimer: DispatchWorkItem?
    @State var exportError: String?
    @State var exportProgress = 0
    @State var exportTotal = 0
    @State var exportTask: Task<Void, Never>?
    @State var isDeletingProject = false
    @State var isResettingProject = false
    @State var resetTemplate: ProjectTemplate?
    // Loaded in `.task`: an init-time scan re-ran on every ancestor body re-eval only to be discarded.
    @State var projectTemplates: [ProjectTemplate] = []
    #if os(macOS)
    @State var gestureZoomStartLevel: CGFloat?
    #endif
    @State var editorViewportHeight: CGFloat = 0
    @State var scrollWheelMonitor: Any?
    @State var showingASCUploadSheet = false
    @State var showingGooglePlayUploadSheet = false
    @State var showcasePresentation: ShowcasePresentation?
    @State var projectNamePrompt: ProjectNamePrompt?
    #if os(iOS)
    @State var pendingExport: PendingExport?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            LocaleBar(state: state)

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
                            EditorRowView(
                                state: state,
                                row: row,
                                requestShowcaseExport: { presentShowcaseSheet(for: $0, mode: .singleRow) }
                            )
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
                #if os(macOS)
                // Trackpad pinch-to-zoom (macOS only — iPad uses the toolbar zoom).
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
                #endif
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
                .background(Color.platformWindowBackground)
                #if os(iOS)
                // Reserve scroll room equal to the floating chrome so the bottom of a tall shape
                // can be scrolled clear of it. Must be applied BEFORE the overlay below — the
                // margins propagate to every descendant ScrollView, and the properties bar's
                // horizontal section scroller would otherwise inherit the bottom inset and
                // inflate the bar's height.
                .contentMargins(.bottom, floatingBottomChromeMargin, for: .scrollContent)
                // Floating bottom chrome: the rich-text format bar (while editing text) stacked
                // above the shape-properties bar, both hovering over the canvas with a transparent
                // surround. `richTextSelectionState` is read so the format bar appears once the
                // controller publishes.
                .overlay(alignment: .bottom) {
                    VStack(spacing: 8) {
                        if state.isEditingText, state.richTextSelectionState != nil,
                           let controller = state.richTextFormatController {
                            RichTextDockedBar(controller: controller)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if state.hasSelection {
                            ShapePropertiesBar(state: state)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.bottom, 8)
                }
                #endif
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    editorViewportHeight = newValue
                }
            }

            #if os(macOS)
            if state.hasSelection {
                Divider()
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
        .animation(.easeInOut(duration: 0.2), value: state.hasSelection)
        #if os(iOS)
        .animation(.easeInOut(duration: 0.2), value: state.isEditingText)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Keyboard avoidance shrinks the canvas ScrollView; scroll the row being edited into
            // the now-smaller visible area so the text isn't hidden behind the keyboard. Re-read
            // the selected row inside the delay so switching shapes mid-delay scrolls the right row.
            guard state.isEditingText else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                guard state.isEditingText, let rowId = state.selectedRowId else { return }
                state.requestCanvasFocus(on: rowId, animated: true)
            }
        }
        #endif
        #if os(macOS)
        .onExitCommand {
            if state.hasSelection {
                state.selectedShapeIds = []
            } else if state.selectedRowId != nil {
                state.deselectAll()
            }
        }
        #endif
        #if os(macOS)
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
            // macOS + in-editor re-opens/switches only: blocks during the brief structural-open
            // phase (hides the teardown→reload flash). On iPad the cold first open is owned by
            // `ProjectOpenGate`, which paints this same spinner before ContentView is built.
            // Image downsampling streams in behind the live UI so row controls stay visible.
            if !isExporting && state.isOpeningProject {
                ProjectLoadingOverlay(message: "Opening Project…")
            }
        }
        #if os(macOS)
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
                .frame(minHeight: 200)
        }
        #else
        // Docked side panel only at regular width. Apple's `.inspector` ignores
        // presentation-detent resizing when it auto-adapts to a sheet (it snaps back to
        // full height), so present a real `.sheet` at compact width instead, where detents
        // resize and the grabber persist properly.
        .inspector(isPresented: Binding(
            get: { !isInspectorCompact && isInspectorPresented },
            set: { if !isInspectorCompact { isInspectorPresented = $0 } }
        )) {
            InspectorPanel(state: state)
                .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
                .frame(minHeight: 200)
        }
        .sheet(isPresented: Binding(
            get: { isInspectorCompact && isInspectorPresented },
            set: { isInspectorPresented = $0 }
        )) {
            InspectorPanel(state: state)
                .presentationDetents(BarSheet.detents(compact: isInspectorCompact), selection: $inspectorSheetDetent)
                .presentationDragIndicator(.visible)
        }
        #endif
        .toolbar(id: "main") {
            // On iPad the Projects home screen + back button own project navigation,
            // so the editor toolbar drops the project name / actions menu.
            #if os(macOS)
            ToolbarItem(id: "projectSwitcher", placement: .navigation) {
                projectSwitcherToolbarMenu
                    .padding(.leading, 8)
            }

            ToolbarItem(id: "projectActions", placement: .navigation) {
                projectActionsToolbarMenu
            }
            #endif

            #if os(macOS)
            ToolbarItem(id: "export", placement: .principal) {
                exportControlGroup
            }

            if !store.isProUnlocked {
                ToolbarItem(id: "buyPro", placement: .principal) {
                    Button {
                        store.presentPaywall(for: .general)
                    } label: {
                        Label("Upgrade to Pro", systemImage: "crown")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Unlock all projects, rows, and templates")
                    .coachPopover(step: .pro, state: state, arrowEdge: .top)
                }
            }

            ToolbarItem(id: "trailingControls", placement: .primaryAction) {
                HStack(spacing: 6) {
                    ZoomControls(onFit: fitZoomToWindow, fitHelpText: fitZoomHelpText)
                    Divider()
                        .frame(height: 16)
                    inspectorToggleButton
                }
            }
            #else
            // Compact width (iPhone, narrow Split View) keeps the title in the roomy
            // center slot and drops the Buy Pro capsule — the leading cluster can't
            // also fit the title next to back/undo/redo/locale there.
            if horizontalSizeClass == .compact {
                ToolbarItem(id: "iPadTitleCompact", placement: .principal) {
                    iPadProjectTitleMenu
                }
            } else {
                if !store.isProUnlocked {
                    ToolbarItem(id: "iPadBuyPro", placement: .principal) {
                        iPadBuyProButton
                            .coachPopover(step: .pro, state: state, arrowEdge: .top)
                    }
                }

                ToolbarItem(id: "iPadTitle", placement: .topBarLeading) {
                    iPadProjectTitleMenu
                }
            }

            ToolbarItem(id: "iPadUndo", placement: .navigation) {
                iPadUndoButton
            }
            ToolbarItem(id: "iPadRedo", placement: .navigation) {
                iPadRedoButton
            }
            ToolbarItem(id: "iPadLocale", placement: .navigation) {
                LocaleToolbarButton(state: state)
            }

            ToolbarItem(id: "iPadZoom", placement: .primaryAction) {
                iPadZoomMenu
            }
            ToolbarItem(id: "iPadInspector", placement: .primaryAction) {
                inspectorToggleButton
            }
            ToolbarItem(id: "iPadExport", placement: .primaryAction) {
                iPadExportControl
            }
            #endif

        }
        #if os(macOS)
        .toolbarRole(.editor)
        #endif
        .onChange(of: store.isProUnlocked, initial: true) { _, isUnlocked in
            state.coachProStepAvailable = !isUnlocked
        }
        // The inspector step anchors inside the inspector, which the user may have closed.
        .onChange(of: state.coachStep) { _, step in
            openInspectorIfCoachNeedsIt(step)
        }
        #if os(iOS)
        // Open it during the transition gap so the anchor is laid out before the
        // popover presents — iPadOS won't present from a not-yet-visible anchor.
        .onChange(of: state.coachPreparingStep) { _, step in
            openInspectorIfCoachNeedsIt(step)
        }
        #endif
        #if os(iOS)
        // Without inline mode iPadOS reserves a large-title header, leaving a blank
        // band between the nav bar and the editor content.
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the editor mid-tour (back to Projects, tab switch) would otherwise
        // strand a coach step with no anchor — no popover, no way to end the tour.
        .onDisappear { state.cancelActiveCoach() }
        // The inspector is a docked side panel at regular width (iPad/Mac) but a blocking
        // sheet at compact width (iPhone) — don't auto-present it there, or it covers the
        // canvas on open. The toolbar toggle still opens it on demand.
        .onAppear {
            if horizontalSizeClass == .compact {
                isInspectorPresented = false
            }
        }
        #endif
        .exportFailedAlert($exportError)
        #if os(iOS)
        .sheet(item: $pendingExport, onDismiss: { discardPendingExport() }) { _ in
            ExportDestinationSheet(title: pendingExportTitle) { destination in
                runPendingExport(to: destination)
            }
        }
        #endif
        .alert(resetTemplate != nil ? String(localized: "Reset Project from Template") : String(localized: "Reset Project"), isPresented: $isResettingProject) {
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
        // On iPad the paywall/celebration sheets live at the navigation root (`iPadRootView`)
        // so they also present from the Projects home screen, not just the pushed editor.
        #if os(macOS)
        .sheet(isPresented: Binding(get: { store.showPaywall }, set: { _ in store.dismissPaywall() }),
               onDismiss: { store.presentPendingCelebrationIfNeeded() }) {
            PaywallSheetContent(store: store)
        }
        .sheet(isPresented: Binding(get: { store.purchaseCelebrationContext != nil }, set: { if !$0 { store.dismissPurchaseCelebration() } })) {
            PostPurchaseCelebrationView(context: store.purchaseCelebrationContext ?? .general) {
                store.dismissPurchaseCelebration()
            }
        }
        .sheet(isPresented: $showingASCUploadSheet) {
            UploadToAppStoreConnectView()
                .environment(state)
        }
        .sheet(isPresented: $showingGooglePlayUploadSheet) {
            UploadToGooglePlayView()
                .environment(state)
        }
        #else
        // iPad: the upload wizard is a desktop-grade multi-step flow — present it as its own
        // full-screen screen with a native nav bar (it builds its own NavigationStack).
        .fullScreenCover(isPresented: $showingASCUploadSheet) {
            UploadToAppStoreConnectView()
                .environment(state)
        }
        .fullScreenCover(isPresented: $showingGooglePlayUploadSheet) {
            UploadToGooglePlayView()
                .environment(state)
        }
        #endif
        .sheet(item: $projectNamePrompt) { prompt in
            ProjectNameSheet(prompt: prompt)
        }
        #if os(macOS)
        .sheet(item: $showcasePresentation) { presentation in
            showcaseExportScreen(for: presentation)
                .presentationSizing(.page)
        }
        #else
        // iPad: showcase export is a desktop-grade split view — present it as its own
        // full-screen screen with a native nav bar rather than a fitted sheet.
        .fullScreenCover(item: $showcasePresentation) { presentation in
            showcaseExportScreen(for: presentation)
                .exportFailedAlert($exportError)
        }
        #endif
        .middleMousePan()
        .task {
            projectTemplates = TemplateService.availableTemplates()
        }
        .onAppear {
            state.undoManager = undoManager
            undoManager?.levelsOfUndo = 50
            #if os(iOS)
            if state.selectedRowId == nil, let firstRow = state.rows.first {
                state.selectRow(firstRow.id)
            }
            #endif
            #if os(macOS)
            scrollWheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.modifierFlags.contains(.command) else { return event }
                let delta = event.hasPreciseScrollingDeltas
                    ? event.scrollingDeltaY * 0.005
                    : event.scrollingDeltaY * 0.05
                state.setZoomLevel(state.zoomLevel + delta, animated: false)
                return nil
            }
            #endif
        }
        .onDisappear {
            #if os(macOS)
            if let monitor = scrollWheelMonitor {
                NSEvent.removeMonitor(monitor)
                scrollWheelMonitor = nil
            }
            #endif
        }
    }

    private func openInspectorIfCoachNeedsIt(_ step: OnboardingCoachStep?) {
        if step == .inspector {
            isInspectorPresented = true
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(StoreService())
}
