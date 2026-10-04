#if os(macOS)
import AppKit
#else
import UIKit
#endif
import StoreKit
import SwiftUI

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
    @Environment(PurchaseService.self) var store
    #if os(iOS)
    /// Always-reserved scroll room so canvas content can clear the floating
    /// editor-mode pill (44pt tall + 16pt inset + an 8pt gap).
    let editorModeFabClearance: CGFloat = 68
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    // macOS-only: see AppRootView — \.openWindow must not be read on iPadOS.
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    #endif
    @Environment(\.requestReview) var requestReview
    @Environment(\.openURL) var openURL
    @AppStorage(AppSettingsKeys.exportFormat) var exportFormat = AppSettingsKeys.Default.exportFormat
    @AppStorage(AppSettingsKeys.exportCustomSuffix) var exportCustomSuffix = ""
    @AppStorage(AppSettingsKeys.openExportFolderOnSuccess) var openExportFolderOnSuccess = AppSettingsKeys.Default.openExportFolderOnSuccess
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    /// Observation only — `ExportFolderBookmark` owns every read and write of the bookmark pair.
    /// Reading the path here is what re-renders the export button when Settings clears it.
    @AppStorage(ExportFolderBookmark.pathKey) var lastExportFolderPath = ""
    @AppStorage(AppSettingsKeys.projectSortOrder) var projectSortOrder = AppSettingsKeys.Default.projectSortOrder
    @AppStorage("inspectorPresented") var isInspectorPresented = true
    #if os(macOS)
    @AppStorage(AppSettingsKeys.selectionInspector) var isSelectionInspectorEnabled = AppSettingsKeys.Default.selectionInspector
    #endif
    #if os(iOS)
    @State var inspectorSheetDetent: PresentationDetent = .large
    #endif
    @State var exportFlow = ExportFlowModel()
    @State var isDeletingProject = false
    @State var isResettingProject = false
    @State var resetTemplate: ProjectTemplate?
    // Loaded in `.task`: an init-time scan re-ran on every ancestor body re-eval only to be discarded.
    @State var projectTemplates: [ProjectTemplate] = []
    // macOS: trackpad pinch. iOS: view-mode two-finger pinch.
    @State var gestureZoomStartLevel: CGFloat?
    @State var editorViewportHeight: CGFloat = 0
    @State var editorViewportWidth: CGFloat = 0
    @State var scrollWheelZoom = PlatformScrollWheelZoom()
    @State var showingASCUploadSheet = false
    @State var showingASCMetadataSheet = false
    @State var showingGooglePlayUploadSheet = false
    @State var showingASCExperimentSheet = false
    @State var showcasePresentation: ShowcasePresentation?
    /// Which way the developer rating sheet was left, read once by `reportDeveloperRatingOutcome`.
    @State var didRateFromDeveloperSheet = false
    @State var projectNamePrompt: ProjectNamePrompt?

    var body: some View {
        contentModals(coreContent)
            // One reporter for every drop handler in the tree, and in the sheets it presents.
            .environment(\.reportDropFailure, DropFailureReporter(state: state))
    }

    /// Kept out of the tree until `.building`: `.id(state.activeProjectId)` on the ScrollView
    /// rebuilds this whole subtree, and without the gate that rebuild re-realizes every row of
    /// the *outgoing* project before the loading overlay can paint.
    @ViewBuilder
    private var editorRows: some View {
        let variantFilter = state.effectiveVariantFilter
        let visibleRows = variantFilter == .all ? state.rows : state.rows.filter(variantFilter.includes)
        let firstRowId = visibleRows.first?.id
        let lastRowId = visibleRows.last?.id
        let isOnlyRow = state.rows.count == 1
        let variantContexts = RowVariantContext.all(for: state)
        // Selection is read here, once, rather than in every row's body. Reading it per row put
        // `\AppState.selectedRowId` in every row's tracking scope, so moving the selection to
        // another row rebuilt every visible canvas; passed down as a value it goes through the
        // `.equatable()` below, which lets all but the two affected rows keep their bodies.
        let selectedRowId = state.selectedRowId
        let selectedShapeIds = state.selectedShapeIds
        ForEach(visibleRows) { row in
            // `.equatable()` so an edit in one row doesn't re-run every visible row's body
            // (see EditorRowView's Equatable).
            let isSelected = row.id == selectedRowId
            EditorRowView(
                state: state,
                row: row,
                isFirst: row.id == firstRowId,
                isLast: row.id == lastRowId,
                isOnlyRow: isOnlyRow,
                variantContext: variantContexts[row.id],
                isSelected: isSelected,
                selectedShapeIds: isSelected ? selectedShapeIds : [],
                requestShowcaseExport: { presentShowcaseSheet(for: $0, mode: .singleRow) }
            )
                .equatable()
                .id(row.id)
            Divider()
        }

        AddRowButton {
            store.requirePro(
                allowed: store.canAddRow(currentCount: state.rows.count),
                context: .rowLimit
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.addRow(variantId: variantFilter.newRowVariantId)
                }
            }
        }
    }

    /// The editor shell: canvas, inspector, toolbar, and canvas-level change handlers.
    private var coreContent: some View {
        inspectorPresentation(editorOverlays(editorColumn))
        .toolbar(id: "main") { mainToolbar }
        #if os(macOS)
        .toolbarRole(.editor)
        #endif
        .onChange(of: store.isProUnlocked, initial: true) { _, isUnlocked in
            state.coach.proStepAvailable = !isUnlocked
        }
        // The inspector step anchors inside the inspector, which the user may have closed.
        .onChange(of: state.coach.step) { _, step in
            openInspectorIfCoachNeedsIt(step)
        }
        #if os(iOS)
        // Open it during the transition gap so the anchor is laid out before the
        // popover presents — iPadOS won't present from a not-yet-visible anchor.
        .onChange(of: state.coach.preparingStep) { _, step in
            openInspectorIfCoachNeedsIt(step)
        }
        #endif
        #if os(iOS)
        // Without inline mode iPadOS reserves a large-title header, leaving a blank
        // band between the nav bar and the editor content.
        .navigationBarTitleDisplayMode(.inline)
        // Leaving the editor mid-tour (back to Projects, tab switch) would otherwise
        // strand a coach step with no anchor — no popover, no way to end the tour.
        .onDisappear { state.coach.cancelActive() }
        // The inspector is a docked side panel at regular width (iPad/Mac) but a blocking
        // sheet at compact width (iPhone) — don't auto-present it there, or it covers the
        // canvas on open. The toolbar toggle still opens it on demand.
        .onAppear {
            if horizontalSizeClass == .compact {
                isInspectorPresented = false
            }
        }
        #endif
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            LocaleBar(state: state)

            LocaleBanner(state: state)
                .alert(state.saveErrorTitle ?? String(localized: "Save Failed"), isPresented: .init(
                    get: { state.saveError != nil },
                    set: { if !$0 { state.dismissSaveError() } }
                )) {
                    Button("OK") { state.dismissSaveError() }
                } message: {
                    Text(state.saveError ?? "")
                }

            ScrollViewReader { proxy in
                EditorRowsScrollView {
                    if state.projectOpen.showsEditorContent { editorRows }
                }
                .id(state.activeProjectId)
                // Bottom-leading: top-trailing sits on the first row header's action buttons, and
                // the bottom-right corner is the iPad view-mode FAB.
                .overlay(alignment: .bottomLeading) {
                    CanvasImageLoadingPill(progress: state.projectOpen)
                        .padding(.leading, 12)
                        .padding(.bottom, imageLoadingPillBottomPadding)
                }
                // macOS: trackpad pinch. iPad: two-finger pinch in view mode only.
                .canvasPinchZoom(state: state, startLevel: $gestureZoomStartLevel)
                .onChange(of: state.canvasFocus.rowRequestNonce) { _, _ in
                    guard let rowId = state.canvasFocus.rowId else { return }
                    if state.canvasFocus.animated {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(rowId, anchor: .center)
                        }
                    } else {
                        proxy.scrollTo(rowId, anchor: .center)
                        state.canvasFocus.animated = true
                    }
                    state.canvasFocus.rowId = nil
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
                .contentMargins(.bottom, max(floatingBottomChromeMargin, editorModeFabClearance), for: .scrollContent)
                .overlay(alignment: .bottom) { floatingBottomChrome }
                .overlay(alignment: .bottomTrailing) { positionedEditorModeButton }
                #endif
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { newValue in
                    editorViewportHeight = newValue.height
                    editorViewportWidth = newValue.width
                }
                .environment(\.editorViewportWidth, editorViewportWidth)
            }

            #if os(macOS)
            if showsPropertiesBar {
                Divider()
                ShapePropertiesBar(state: state)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            #endif
        }
        #if os(iOS)
        // Only the format bar animates. The properties bar shows and hides instantly, so it must
        // not pick up an ambient animation from here either — it appears the moment you select.
        .animation(.easeInOut(duration: 0.2), value: state.textEdit.isActive)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            // Keyboard avoidance shrinks the canvas ScrollView; scroll the row being edited into
            // the now-smaller visible area so the text isn't hidden behind the keyboard. Re-read
            // the selected row inside the delay so switching shapes mid-delay scrolls the right row.
            guard state.textEdit.isActive else { return }
            Task.delayed(0.35) {
                guard state.textEdit.isActive, let rowId = state.selectedRowId else { return }
                state.requestCanvasFocus(on: rowId, animated: true)
            }
        }
        #endif
    }
}

#Preview {
    let state = AppState()
    ContentView()
        .environment(state)
        .environment(state.zoom)
        .environment(state.iCloudStatus)
        .environment(PurchaseService())
}
