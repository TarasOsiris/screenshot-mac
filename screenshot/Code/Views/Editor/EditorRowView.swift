import SwiftUI
import UniformTypeIdentifiers

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
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @Environment(\.reportDropFailure) var reportDropFailure
    @State var activeAlert: RowAlert?
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

    var zoom: CGFloat { state.zoom.level }
    let canvasHorizontalPadding: CGFloat = 16

    var isPreviewMode: Bool { state.viewMode.previewingRows.contains(row.id) }

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
        PerfSignpost.bodyEvaluated("EditorRowView.body", row: row.id, count: row.shapes.count)
        return VStack(alignment: .leading, spacing: 0) {
            EditorRowHeader(
                row: row,
                isSelected: isSelected,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                canDelete: canDelete,
                isEditingLabel: $isEditingLabel,
                editingLabelText: $editingLabelText,
                isLabelFieldFocused: $isLabelFieldFocused,
                onToggleCollapsed: toggleCollapsed,
                onStartLabelEdit: startLabelEdit,
                onCommitLabelEdit: commitLabelEdit,
                onCancelLabelEdit: cancelLabelEdit,
                onMoveUp: moveRowUp,
                onMoveDown: moveRowDown,
                onDuplicate: duplicateRow,
                onReset: resetRow,
                onDelete: deleteRow,
                isPreviewMode: isPreviewMode,
                onTogglePreview: togglePreviewMode
            ) {
                rowMenuContent
            }
            .background(isSelected ? Color.accentColor.opacity(UIMetrics.Opacity.accentRowHeader) : Color.clear)

            if !row.isCollapsed {
                horizontalScrollArea
                    .id(scrollAreaRealized || state.canvasScrollMeasurement.isMeasured(row.id))
                    // One-shot, fired the first time this row's scroll area appears: re-key it
                    // once so the inner horizontal ScrollView re-measures against the now-settled
                    // width. A LazyVStack's first lazy pass can propose an unbounded width,
                    // leaving the ScrollView sized to its content and unscrollable. Scoping this
                    // to the scroll area (not the row) means an already-realized row that's
                    // collapsed/expanded mid-session keeps its id and doesn't rebuild.
                    //
                    // "Once" has to outlive the view: the LazyVStack drops the @State of rows it
                    // recycles off-screen, so keeping the flag here alone made every scroll-in
                    // build the whole canvas subtree, tear it down and rebuild it. The registry
                    // is deliberately non-observable, so reading it here tracks nothing.
                    .task {
                        guard !state.canvasScrollMeasurement.isMeasured(row.id) else { return }
                        state.canvasScrollMeasurement.markMeasured(row.id)
                        scrollAreaRealized = true
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
            RowContextMenuPreview(
                row: row,
                localeState: state.localeState,
                screenshotImages: state.screenshotImages,
                availableFontFamilies: state.availableFontFamilySet
            )
        }
        .alert(
            activeAlert?.title ?? "",
            isPresented: $activeAlert.isPresent(),
            presenting: activeAlert
        ) { alert in
            alertActions(for: alert)
        } message: { alert in
            alertMessage(for: alert)
        }
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
