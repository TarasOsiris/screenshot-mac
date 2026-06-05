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
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    @Environment(\.openWindow) var openWindow
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
    @State var isInspectorPresented = true
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
    @State var projectTemplates: [ProjectTemplate] = TemplateService.availableTemplates()
    #if os(macOS)
    @State var gestureZoomStartLevel: CGFloat?
    #endif
    @State var editorViewportHeight: CGFloat = 0
    @State var scrollWheelMonitor: Any?
    @State var showingASCUploadSheet = false
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
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { newValue in
                    editorViewportHeight = newValue
                }
            }

            if state.hasSelection {
                Divider()
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state.hasSelection)
        #if os(macOS)
        .onExitCommand {
            if state.hasSelection {
                state.selectedShapeIds = []
            } else if state.selectedRowId != nil {
                state.deselectAll()
            }
        }
        #endif
        #if DEBUG
        .overlay {
            if state.isEditingText,
               let selectionState = state.richTextSelectionState,
               selectionState.hasRangeSelection,
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
        .inspector(isPresented: $isInspectorPresented) {
            InspectorPanel(state: state)
                #if os(macOS)
                .inspectorColumnWidth(min: 220, ideal: 260, max: 320)
                #else
                .inspectorColumnWidth(min: 340, ideal: 380, max: 480)
                #endif
                .frame(minHeight: 200)
        }
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
            ToolbarItem(id: "iPadTitle", placement: .principal) {
                Text(state.activeProject?.name ?? "")
                    .font(.headline)
                    .lineLimit(1)
            }

            // History section
            ToolbarItem(id: "iPadHistory", placement: .navigation) {
                HStack(spacing: 2) {
                    iPadUndoButton
                    iPadRedoButton
                }
            }

            // Localization: the whole language-toggle bar folded into one globe pull-down.
            // Sits on the leading edge near the title — kept out of the trailing control cluster.
            ToolbarItem(id: "iPadLocale", placement: .topBarLeading) {
                LocaleToolbarButton(state: state)
            }

            // View / output section: zoom, divided from the export action.
            // An id-based toolbar requires ToolbarItem (not ToolbarItemGroup), so the
            // sub-groups live inside one item's HStack with dividers.
            ToolbarItem(id: "iPadViewControls", placement: .primaryAction) {
                HStack(spacing: 8) {
                    iPadZoomOutButton
                    iPadZoomInButton

                    Divider()
                        .frame(height: 20)

                    iPadExportControl
                }
            }

            // Inspector toggle is a separate, rightmost round button.
            ToolbarItem(id: "iPadInspectorToggle", placement: .primaryAction) {
                inspectorToggleButton
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }
            #endif

        }
        .toolbarRole(.editor)
        #if os(iOS)
        // Without inline mode iPadOS reserves a large-title header, leaving a blank
        // band between the nav bar and the editor content.
        .navigationBarTitleDisplayMode(.inline)
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
        #else
        // iPad: the upload wizard is a desktop-grade multi-step flow — present it as its own
        // full-screen screen with a native nav bar (it builds its own NavigationStack).
        .fullScreenCover(isPresented: $showingASCUploadSheet) {
            UploadToAppStoreConnectView()
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
}

#Preview {
    ContentView()
        .environment(AppState())
        .environment(StoreService())
}
