import SwiftUI
import UniformTypeIdentifiers

final class ModelPointStore {
    var value: CGPoint?
}

struct EditorRowView: View {
    @Bindable var state: AppState
    @Environment(StoreService.self) var store
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    let row: ScreenshotRow
    let isFirst: Bool
    let isLast: Bool
    let requestShowcaseExport: (ScreenshotRow) -> Void
    @AppStorage("confirmBeforeDeleting") var confirmBeforeDeleting = true
    @State var isDeletingRow = false
    @State var isResettingRow = false
    @State var isSvgDialogPresented = false
    @State var contextMenuPointStore = ModelPointStore()
    @State var dragSession = CanvasDragSession()
    @State var isEditingLabel = false
    @State var editingLabelText = ""
    /// True when the current mode (Edit or Preview) has had a chance to paint
    /// its first frame. Flipped to false on every Edit↔Preview toggle so we
    /// can show a `ProgressView` instead of a frozen UI for slow rows
    /// (many shapes, blur backgrounds). Starts true so the initial editor
    /// render on app open is instant.
    @State var modeReady = true
    @State var exportError: String?
    #if DEBUG
    @State var simulatorCaptureError: String?
    @State var simulatorInstallPromptShapeId: UUID?
    #endif
    @State var backgroundRemovalError: String?
    @State var textEditingShapeId: UUID?
    /// Drives the one-shot re-key of `horizontalScrollArea` (see its `.task`).
    @State var scrollAreaRealized = false
    @FocusState var isLabelFieldFocused: Bool

    var isSelected: Bool {
        state.selectedRowId == row.id
    }

    var canMoveUp: Bool { !isFirst }
    var canMoveDown: Bool { !isLast }
    /// The only undeletable row is the sole row — i.e. both first and last.
    var canDelete: Bool { !(isFirst && isLast) }

    var zoom: CGFloat { state.zoomLevel }
    let canvasHorizontalPadding: CGFloat = 16

    var isPreviewMode: Bool { state.previewingRows.contains(row.id) }

    @ViewBuilder
    private var selectionRule: some View {
        if isSelected {
            Rectangle()
                .fill(Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: UIMetrics.BorderWidth.prominent)
                .allowsHitTesting(false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorRowHeader(
                row: row,
                isSelected: isSelected,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                canDelete: canDelete,
                isEditingLabel: $isEditingLabel,
                editingLabelText: $editingLabelText,
                isLabelFieldFocused: $isLabelFieldFocused,
                onToggleCollapsed: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        state.toggleRowCollapsed(for: row.id)
                    }
                },
                onStartLabelEdit: startLabelEdit,
                onCommitLabelEdit: commitLabelEdit,
                onCancelLabelEdit: cancelLabelEdit,
                onMoveUp: {
                    withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
                },
                onMoveDown: {
                    withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
                },
                onDuplicate: {
                    store.requirePro(
                        allowed: store.canAddRow(currentCount: state.rows.count),
                        context: .rowLimit
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
                    }
                },
                onReset: {
                    if confirmBeforeDeleting {
                        isResettingRow = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
                    }
                },
                onDelete: {
                    if confirmBeforeDeleting {
                        isDeletingRow = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
                    }
                },
                isPreviewMode: isPreviewMode,
                onTogglePreview: {
                    modeReady = false
                    let wasPreview = isPreviewMode
                    state.togglePreview(for: row.id)
                    if !wasPreview {
                        textEditingShapeId = nil
                        dragSession.reset()
                    }
                }
            ) {
                rowMenuContent
            }
            .background(isSelected ? Color.accentColor.opacity(UIMetrics.Opacity.accentRowHeader) : Color.clear)

            if !row.isCollapsed {
                horizontalScrollArea
                    .id(scrollAreaRealized)
                    // One-shot, fired the first time the scroll area appears (at launch, or
                    // when an initially-collapsed row is expanded): re-key it once so the
                    // inner horizontal ScrollView re-measures against the now-settled width.
                    // A LazyVStack's first lazy pass can propose an unbounded width, leaving
                    // the ScrollView sized to its content and unscrollable. Scoping this to
                    // the scroll area (not the row) means an already-realized row that's
                    // collapsed/expanded mid-session keeps its id and doesn't rebuild.
                    .task {
                        if !scrollAreaRealized { scrollAreaRealized = true }
                    }
                    // Launch the deferred onboarding tour once the first canvas (the `.canvas`
                    // anchor lives inside it) is on screen — the pending flag is armed at first
                    // launch, before any project exists.
                    .onAppear { startDeferredCoachIfNeeded() }
                    // Retry after a project open completes — on iPad the canvas can appear
                    // while `isOpeningProject` is still true, and no other trigger re-fires.
                    .onChange(of: state.isOpeningProject) { _, _ in
                        startDeferredCoachIfNeeded()
                    }
                    #if os(iOS)
                    // Retry when leaving compact width (Split View → full screen), where
                    // the tour was deferred because the inspector presents as a sheet.
                    .onChange(of: horizontalSizeClass) { _, _ in
                        startDeferredCoachIfNeeded()
                    }
                    #endif
            }
        }
        .onScrollGeometryChange(for: CGRect.self) { geo in
            geo.visibleRect
        } action: { _, visibleRect in
            guard isSelected else { return }
            let canvasX = max(0, visibleRect.midX - canvasHorizontalPadding)
            state.visibleCanvasModelCenter = CGPoint(
                x: canvasX / row.displayScale(zoom: zoom),
                y: row.templateHeight / 2
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { tapSelectRow() }
        .background(isSelected ? Color.accentColor.opacity(UIMetrics.Opacity.accentRowSelection) : Color.clear)
        .overlay(alignment: .top) { selectionRule }
        .overlay(alignment: .bottom) { selectionRule }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .contextMenuWithPreview {
            rowMenuContent
        } preview: {
            RowContextMenuPreview(state: state, row: row)
        }
        .alert("Delete Row", isPresented: $isDeletingRow) {
            Button("Delete", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(row.label)\"?")
        }
        .alert("Reset Row", isPresented: $isResettingRow) {
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all screenshots and shapes from \"\(row.label)\" and restore default settings.")
        }
        .alert("Export Failed", isPresented: $exportError.isPresent()) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        #if DEBUG
        .alert("iOS Simulator Capture Failed", isPresented: $simulatorCaptureError.isPresent()) {
            Button("OK") { simulatorCaptureError = nil }
        } message: {
            Text(simulatorCaptureError ?? "")
        }
        #endif
        .alert("Remove Background Failed", isPresented: $backgroundRemovalError.isPresent()) {
            Button("OK") { backgroundRemovalError = nil }
        } message: {
            Text(backgroundRemovalError ?? "")
        }
        #if DEBUG && os(macOS)
        .alert("Enable iOS Simulator Capture", isPresented: $simulatorInstallPromptShapeId.isPresent()) {
            Button("Install…") {
                let pendingShapeId = simulatorInstallPromptShapeId
                simulatorInstallPromptShapeId = nil
                Task { @MainActor in
                    switch SimulatorCaptureService.presentInstallPanel() {
                    case .success:
                        if let pendingShapeId {
                            state.captureFromSimulator(intoShape: pendingShapeId) { message in
                                simulatorCaptureError = message
                            }
                        }
                    case .failure(let error):
                        if let message = error.errorDescription {
                            simulatorCaptureError = message
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                simulatorInstallPromptShapeId = nil
            }
        } message: {
            Text("Capturing from the iOS Simulator needs a one-time setup: a small script that asks the Simulator for a screenshot and does nothing else.\n\nBecause of macOS security, only you can install it. Click Install… to save the script — you'll only need to do this once.")
        }
        #endif
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size, useColor, color in
                let center = contextMenuPointStore.value ?? state.shapeCenter(for: row)
                let maxDim = row.svgMaxDimension
                let scaledSize = SvgHelper.scaledSize(size, maxDim: maxDim)
                var shape = CanvasShapeModel.defaultSvg(centerX: center.x, centerY: center.y, svgContent: svgContent, size: scaledSize)
                if useColor {
                    shape.svgUseColor = true
                    shape.color = color
                }
                state.addShape(shape)
            }
        }
    }
}

/// Used via `.equatable()` in ContentView so an edit in one row doesn't re-run
/// every visible row's body. `state` is a stable reference and the closure only
/// touches stable @State storage, so comparing the value inputs is sufficient;
/// properties the body reads off `state` still trigger via @Observable tracking.
extension EditorRowView: Equatable {
    static func == (lhs: EditorRowView, rhs: EditorRowView) -> Bool {
        lhs.row == rhs.row
            && lhs.isFirst == rhs.isFirst
            && lhs.isLast == rhs.isLast
    }
}
