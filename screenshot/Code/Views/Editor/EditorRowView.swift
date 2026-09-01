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
    /// Selection arrives as a value input rather than being read off `state`. Reading
    /// `state.selectedRowId` in the body put it in *every* realized row's tracking scope, so moving
    /// the selection to another row invalidated all of them — `.equatable()` can't intercept that,
    /// because Observation marks the body dirty directly. Same reasoning as `isFirst`/`isLast`.
    let isSelected: Bool
    /// The shapes selected *in this row*; empty when the selection lives elsewhere.
    let selectedShapeIds: Set<UUID>
    let requestShowcaseExport: (ScreenshotRow) -> Void
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @Environment(\.reportDropFailure) var reportDropFailure
    @State var activeAlert: RowAlert?
    @State var isSvgDialogPresented = false
    @State var contextMenuPointStore = ModelPointStore()
    /// The one template whose background popover is open, if any — see `TemplateControlBar`.
    @State var backgroundPopoverTemplateId: UUID?
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
    /// The shape whose image the row's single picker is currently choosing, if any. One presentation
    /// host per row instead of one per image/device shape — see `imagePickerHost`.
    ///
    /// Deliberately not the presentation flag as well: SwiftUI writes `false` into that binding while
    /// tearing the picker down, and on iPad the confirmation dialog closes a whole photo-picker before
    /// the image arrives — so a target read back through the binding is always nil by delivery time.
    @State var pickerTargetShapeId: UUID?
    @State var isImagePickerPresented = false
    @FocusState var isLabelFieldFocused: Bool

    var canMoveUp: Bool { !isFirst }
    var canMoveDown: Bool { !isLast }
    /// The only undeletable row is the sole row — i.e. both first and last.
    var canDelete: Bool { !(isFirst && isLast) }

    var zoom: CGFloat { state.zoom.level }
    var isPreviewMode: Bool { state.viewMode.previewingRows.contains(row.id) }

    /// Always mounted, faded by opacity rather than inserted/removed. The fade has to be driven from
    /// the chrome itself: an `.animation(value: isSelected)` on the row would put the whole canvas
    /// — every `CanvasShapeView`, and the handle overlay being installed on one row and torn down on
    /// the other — inside a 0.15s transaction, which is what `19e7ffe1` and `a0183ac5` removed
    /// elsewhere. Interpolating opacity also beats animating a `Color.accentColor`/`.clear` swap,
    /// which is an identity change SwiftUI can only cross-fade.
    private var selectionRule: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: UIMetrics.BorderWidth.prominent)
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(false)
            .animation(Self.selectionFade, value: isSelected)
    }

    private static let selectionFade: Animation = .easeInOut(duration: 0.15)

    private func selectionTint(_ base: Double) -> some View {
        // `Rectangle().fill()` rather than a bare `Color`: on `Color`, `.opacity(_:)` resolves to
        // `Color.opacity -> Color`, so it would animate a color *value* instead of the view's
        // opacity — which is the thing this is trying to avoid.
        Rectangle()
            .fill(Color.accentColor.opacity(base))
            .opacity(isSelected ? 1 : 0)
            .animation(Self.selectionFade, value: isSelected)
    }

    var body: some View {
        PerfSignpost.bodyEvaluated("EditorRowView.body", row: row.id, count: row.shapes.count)
        return Color.clear
            .frame(height: EditorRowLayout.rowHeight(row: row, zoom: zoom, isPreviewMode: isPreviewMode))
            .overlay(alignment: .topLeading) { rowContent }
    }

    /// The row's real content, rendered in an `.overlay` of the fixed-height shell above.
    ///
    /// Overlay content never participates in its parent's sizing, so the editor's `LazyVStack` gets
    /// the row's height from `EditorRowLayout` without descending into the header, the horizontal
    /// `ScrollView`, the padding chain or the control bars. That descent was the largest cost in a
    /// scrollbar-drag trace. It also hands this subtree a *finite* width on its very first layout
    /// pass, which is what makes the old one-shot re-key unnecessary.
    @ViewBuilder
    private var rowContent: some View {
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
            .frame(height: EditorRowLayout.headerHeight)
            .background { selectionTint(UIMetrics.Opacity.accentRowHeader) }
            // Scoped to the header, which is pure chrome: it restores the fade its label, chevron
            // and ellipsis had from the row-wide animation this replaced, without putting the
            // canvas back inside an animated transaction.
            .animation(Self.selectionFade, value: isSelected)

            if !row.isCollapsed {
                // No re-key here any more. It existed because a `LazyVStack`'s first lazy pass can
                // propose an unbounded width, leaving the inner horizontal `ScrollView` sized to its
                // content and unscrollable; the fix was to rebuild the subtree once against the
                // settled width, which cost every row two full canvas builds on first realization.
                // The shell above is `Color.clear`, so it takes the proposed width and hands this
                // subtree a finite one immediately — there is nothing to correct.
                horizontalScrollArea
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
        .contentShape(Rectangle())
        .onTapGesture { tapSelectRow() }
        .background { selectionTint(UIMetrics.Opacity.accentRowSelection) }
        .overlay(alignment: .top) { selectionRule }
        .overlay(alignment: .bottom) { selectionRule }
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
            && lhs.isSelected == rhs.isSelected
            && lhs.selectedShapeIds == rhs.selectedShapeIds
    }
}
