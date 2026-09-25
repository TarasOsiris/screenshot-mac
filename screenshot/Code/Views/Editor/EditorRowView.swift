import SwiftUI
import UniformTypeIdentifiers

struct EditorRowView: View {
    @Bindable var state: AppState
    @Environment(PurchaseService.self) var store
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    let row: ScreenshotRow
    /// First/last among the rows the editor shows, which a variant filter can narrow.
    let isFirst: Bool
    let isLast: Bool
    let isOnlyRow: Bool
    let variantContext: RowVariantContext?
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
    @Environment(EditorScrollState.self) private var scrollState
    @State var activeAlert: RowAlert?
    @State var isSvgDialogPresented = false
    @State var svgReplaceTarget: CanvasShapeModel?
    @State var contextMenuPointStore = ModelPointStore()
    /// Latched once this row has mounted its chrome, so a scroll that starts later cannot take it
    /// away again. Only a row realized *during* a scroll waits.
    @State private var chromeReady = false
    @State var dragSession = CanvasDragSession()
    @State var isEditingLabel = false
    @State var editingLabelText = ""

    /// Shapes this row has language overrides on. Derived from the `row` value input, never from
    /// `state.rows` — reading that here would put the whole document in every realized row's
    /// tracking scope, which `.equatable()` cannot intercept (same reasoning as `isSelected`).
    /// Read once per body, into a local, so the sweep isn't repeated.
    private var overriddenShapeIds: Set<UUID> { state.overriddenShapeIds(in: row) }
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
    var canDelete: Bool { !isOnlyRow }
    /// A copy would be a second row of this size in the same variant.
    var canDuplicate: Bool { row.isOriginal }
    var isLabelLinked: Bool { variantContext?.isLabelLinked ?? false }

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

    /// The row header and the per-template control bars are ~15 controls and, with the bars, three
    /// presentation hosts per template. Building them is a large part of the 100–230 ms freeze a
    /// row costs to materialize, and none of it can be used while the list is moving — so a row
    /// that appears mid-scroll renders canvas-only and fills the same space with `Color.clear`.
    /// The reserved height must stay identical to `EditorRowLayout`'s, or chrome arriving would
    /// shift the layout, which is the very thing this is meant to stop.
    ///
    /// The `||` is load-bearing: `@Observable` tracking registers only what a body actually reads,
    /// so once `chromeReady` is true the scroll flag is never read and this row stops re-running
    /// on every start and end of a scroll. Reading it unconditionally re-ran every realized row
    /// twice per trackpad flick.
    var showsChrome: Bool { chromeReady || !scrollState.isScrolling }

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
            Group {
                if showsChrome {
                    let overridden = overriddenShapeIds
                    EditorRowHeader(
                        row: row,
                        isSelected: isSelected,
                        canMoveUp: canMoveUp,
                        canMoveDown: canMoveDown,
                        canDelete: canDelete,
                        canDuplicate: canDuplicate,
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
                        onTogglePreview: togglePreviewMode,
                        overriddenShapeCount: overridden.count,
                        overrideLocaleLabel: overridden.isEmpty ? "" : state.localeState.activeLocaleLabel,
                        onSelectOverridden: { state.selectShapes(overridden, in: row.id) },
                        variantBadge: variantContext.map { AnyView(VariantBadgeMenu(state: state, row: row, context: $0)) }
                    ) {
                        rowMenuContent
                    }
                    // The header is the chrome's first mount whether the row appeared idle or
                    // waited for a scroll to end, so this is the one place the latch belongs.
                    .onAppear { chromeReady = true }
                } else {
                    Color.clear
                }
            }
            .frame(height: EditorRowLayout.headerHeight)
            .background { selectionTint(UIMetrics.Opacity.accentRowHeader) }
            // Scoped to the header, which is pure chrome: it restores the fade its label, chevron
            // and ellipsis had from the row-wide animation this replaced, without putting the
            // canvas back inside an animated transaction.
            .animation(Self.selectionFade, value: isSelected)
            // Safe here: nothing under the header scrolls.
            .inertWhileEditorScrolls()

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
                    // A `DragGesture` whose view goes away mid-drag never delivers `onEnded`, so
                    // the gesture's frame would keep driving the properties bar.
                    .onDisappear { endCanvasGestures() }
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
                state.insertSvgShape(
                    content: svgContent,
                    naturalSize: size,
                    customColor: useColor ? color : nil,
                    inRow: row.id,
                    at: contextMenuPointStore.value
                )
            }
        }
        .sheet(item: $svgReplaceTarget) { target in
            SvgPasteDialog(
                isPresented: Binding(get: { svgReplaceTarget != nil }, set: { if !$0 { svgReplaceTarget = nil } }),
                replacing: target
            ) { svgContent, size, useColor, color in
                state.replaceSvg(shapeId: target.id, content: svgContent, naturalSize: size, useColor: useColor, color: color)
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
            && lhs.isOnlyRow == rhs.isOnlyRow
            && lhs.variantContext == rhs.variantContext
            && lhs.isSelected == rhs.isSelected
            && lhs.selectedShapeIds == rhs.selectedShapeIds
    }
}
