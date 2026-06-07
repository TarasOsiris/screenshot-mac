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
    let requestShowcaseExport: (ScreenshotRow) -> Void
    @AppStorage("confirmBeforeDeleting") var confirmBeforeDeleting = true
    @State var isDeletingRow = false
    @State var isResettingRow = false
    @State var isSvgDialogPresented = false
    @State var contextMenuPointStore = ModelPointStore()
    @State var activeGuides: [AlignmentGuide] = []
    @State var activeDragOffset: CGSize = .zero
    @State var draggingShapeId: UUID?
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
    /// Cached snap targets for non-selected shapes during drag.
    @State var cachedSnapTargets: [AlignmentService.OtherShapeBounds]?
    /// In-progress resize state per shape, owned by EditorRowView so the
    /// selection overlay and CanvasShapeView see the same value during a drag.
    @State var pendingResize: [UUID: ResizeState] = [:]
    @State var pendingRotation: [UUID: Double] = [:]
    @State var textEditingShapeId: UUID?
    @FocusState var isLabelFieldFocused: Bool

    var isSelected: Bool {
        state.selectedRowId == row.id
    }

    var canMoveUp: Bool {
        state.rows.first?.id != row.id
    }

    var canMoveDown: Bool {
        state.rows.last?.id != row.id
    }

    var canDelete: Bool {
        state.rows.count > 1
    }

    var zoom: CGFloat { state.zoomLevel }
    let canvasHorizontalPadding: CGFloat = 16

    var isPreviewMode: Bool { state.previewingRows.contains(row.id) }

    /// iPad points the first coach mark at the row's first device frame (see
    /// `canvasView`); the scroll-area anchor is only the no-device fallback there.
    var canvasCoachAnchorsOnDevice: Bool {
        #if os(iOS)
        row.activeShapes.contains { $0.type == .device }
        #else
        false
        #endif
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
                        pendingResize = [:]
                        pendingRotation = [:]
                        textEditingShapeId = nil
                        activeDragOffset = .zero
                        draggingShapeId = nil
                        cachedSnapTargets = nil
                        activeGuides = []
                    }
                }
            ) {
                rowMenuContent
            }

            if !row.isCollapsed {
                horizontalScrollArea
                    .coachPopover(
                        step: .canvas,
                        state: state,
                        isActive: state.rows.first?.id == row.id && !isPreviewMode && !canvasCoachAnchorsOnDevice,
                        arrowEdge: .top,
                        attachmentAnchor: .point(.center)
                    )
                    // Launch a deferred onboarding tour once the first canvas (the `.canvas`
                    // anchor) is on screen. `.onAppear` covers the first-launch path (flag set
                    // before this view exists); `.onChange` covers a returning user whose canvas
                    // is already visible when they tap "Get Started".
                    .onAppear { startDeferredCoachIfNeeded() }
                    .onChange(of: state.pendingCoachPersistOnEnd) { _, _ in
                        startDeferredCoachIfNeeded()
                    }
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
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .allowsHitTesting(false)
            }
        }
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
