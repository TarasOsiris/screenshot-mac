import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

extension EditorRowView {
    /// Forwarded from `EditorRowLayout`, which is where the row's geometry is stated and tested.
    var scrollAreaHeight: CGFloat {
        EditorRowLayout.scrollAreaHeight(row: row, zoom: zoom, isPreviewMode: isPreviewMode)
    }

    /// Display-space rect of the shape the picker is targeting, so iPad's dialog pops from it.
    /// Falls back to a degenerate rect at the origin when nothing is targeted — the host is always
    /// mounted, so it always needs somewhere to sit.
    func imagePickerAnchor(in shapes: [CanvasShapeModel], displayScale: CGFloat) -> CGRect {
        guard let id = pickerTargetShapeId, let shape = shapes.first(where: { $0.id == id }) else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: shape.x * displayScale,
            y: shape.y * displayScale,
            width: shape.width * displayScale,
            height: shape.height * displayScale
        )
    }

    var horizontalScrollArea: some View {
        PerfSignpost.bodyEvaluated("EditorRowView.canvas", row: row.id, count: row.templates.count)
        return Color.clear
            .frame(height: scrollAreaHeight)
            .overlay(alignment: .topLeading) { scrollAreaContent }
    }

    private var scrollAreaContent: some View {
        ScrollViewReader { hProxy in
            // `inertWhileEditorScrolls()` must stay on this scroll view's content, below, not here.
            ScrollView(.horizontal) {
                // Render the canvas at full (zoom-inclusive) scale instead of a visual-only
                // `.scaleEffect(zoom)`. Each shape's layout frame then equals its on-screen
                // size, which the iOS context-menu lift anchors to — a presentation-only zoom
                // transform makes the lift mis-scale (shrink on press, snap back on dismiss).
                let dw = row.displayWidth(zoom: zoom)
                let dh = row.displayHeight(zoom: zoom)
                let ds = row.displayScale(zoom: zoom)

                VStack(alignment: .leading, spacing: 0) {
                    if !modeReady {
                        modeLoadingPlaceholder
                    } else if isPreviewMode {
                        RowPreviewView(
                            row: row,
                            zoom: zoom,
                            localeState: state.localeState,
                            screenshotImages: state.screenshotImages,
                            availableFontFamilies: state.availableFontFamilySet
                        )
                    } else {
                        // Sunk into this branch: preview mode doesn't use either, and
                        // RowPreviewView resolves the row's shapes itself — so hoisting these
                        // above the branch resolved every shape twice while previewing.
                        let resolved = LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)

                        HStack(alignment: .top, spacing: 0) {
                            // Unified canvas with per-template scroll anchors. Rendered at
                            // full scale (no `.scaleEffect`) so shape layout frames match
                            // their on-screen size; the selection layer renders the same way.
                            ZStack(alignment: .topLeading) {
                                canvasView(
                                    dw: dw,
                                    dh: dh,
                                    ds: ds,
                                    resolvedShapes: resolved
                                )
                                    .frame(
                                        width: row.totalDisplayWidth(zoom: zoom),
                                        height: row.displayHeight(zoom: zoom),
                                        alignment: .topLeading
                                    )
                                    .overlay(alignment: .topLeading) {
                                        HStack(spacing: 0) {
                                            ForEach(row.templates) { template in
                                                Color.clear
                                                    .frame(width: row.displayWidth(zoom: zoom), height: 1)
                                                    .id("focus_\(template.id)")
                                            }
                                        }
                                    }

                                // Always mounted (renders nothing unless a shape is
                                // selected, which never happens in view mode) so toggling
                                // mode doesn't add/remove a layer mid-animation.
                                CanvasSelectionLayer(
                                    row: row,
                                    resolvedShapes: resolved,
                                    selectedShapeIds: selectedShapeIds,
                                    visualScale: ds,
                                    dragSession: dragSession,
                                    liveShapeEdit: state.liveShapeEdit,
                                    liveShapeGeometry: state.liveShapeGeometry,
                                    textEditingShapeId: textEditingShapeId,
                                    imageCrop: state.imageCrop,
                                    imageSize: { state.displayImageSize(of: $0) },
                                    onUpdate: { state.updateShape($0) }
                                )
                                .frame(
                                    width: row.totalDisplayWidth(zoom: zoom),
                                    height: row.displayHeight(zoom: zoom),
                                    alignment: .topLeading
                                )

                                CanvasMarqueeLayer(dragSession: dragSession, displayScale: ds)
                                    .frame(
                                        width: row.totalDisplayWidth(zoom: zoom),
                                        height: row.displayHeight(zoom: zoom),
                                        alignment: .topLeading
                                    )
                            }

                            AddTemplateButton(width: row.displayWidth(zoom: zoom), height: row.displayHeight(zoom: zoom)) {
                                store.addTemplateIfAllowed(currentCount: row.templates.count) { state.addTemplate(to: row.id) }
                            }
                        }
                        // Canvas geometry is model-space and anchored `.topLeading`; under an RTL
                        // UI language SwiftUI resolves that to the top-right and mirrors the row,
                        // so one project would look different per UI language and diverge from
                        // export. Pin the strip, matching `ViewRasterizer.renderViewToImage`;
                        // chrome outside it still mirrors.
                        .environment(\.layoutDirection, .leftToRight)

                        Group {
                            if showsChrome {
                                controlBarsRow
                            } else {
                                // Same footprint, none of the ~7 controls and 3 presentation hosts
                                // per template. See `EditorRowView.showsChrome`.
                                Color.clear
                                    .frame(
                                        width: row.displayWidth(zoom: zoom) * CGFloat(row.templates.count),
                                        height: UIMetrics.TemplateBar.height
                                    )
                            }
                        }
                        // Bars must not slide during a reorder: the move buttons have to stay
                        // under the cursor so rapid clicks keep landing on a button.
                        .transaction { $0.animation = nil }
                        .padding(.bottom, EditorRowLayout.controlBarsBottomInset)
                    }
                }
                // One `_PaddingLayout` layer, not three: each is a separate layout node that
                // re-measures its child on every sizing pass.
                .padding(EditorRowLayout.scrollContentInsets)
                .inertWhileEditorScrolls()
            }
            // Observes *this* scroll view. It used to sit on the row's root, whose nearest
            // enclosing scroll view is the editor's vertical one — so it reported that scroller's
            // geometry, and every realized row recomputed a `CGRect` on every vertical scroll tick.
            // A scalar is all the one consumer wants (`AppState.shapeCenter(for:)` reads the x).
            .onScrollGeometryChange(for: CGFloat?.self) { geo in
                guard isSelected else { return nil }
                let midX = geo.visibleRect.midX
                let canvasX = max(0, midX - EditorRowLayout.scrollContentInsets.leading)
                return canvasX / row.displayScale(zoom: zoom)
            } action: { _, centerX in
                guard let centerX else { return }
                state.canvasHints.visibleModelCenterX = centerX
            }
            .onChange(of: state.canvasFocus.shapeRequestNonce) { _, _ in
                guard state.selectedRowId == row.id,
                      let shapeId = state.canvasFocus.shapeId,
                      let shape = row.shapes.first(where: { $0.id == shapeId }) else { return }
                let templateIndex = row.owningTemplateIndex(for: shape)
                guard templateIndex < row.templates.count else { return }
                let templateId = row.templates[templateIndex].id
                hProxy.scrollTo("focus_\(templateId)", anchor: .center)
                state.canvasFocus.shapeId = nil
            }
        }
    }

    @ViewBuilder
    var modeLoadingPlaceholder: some View {
        let n = CGFloat(row.templates.count)
        let tileGap = UIMetrics.Preview.tileGap
        // Match whichever mode we're about to render so layout doesn't jump.
        let baseWidth = isPreviewMode
            ? row.displayWidth(zoom: 1.0) * n + tileGap * max(0, n - 1)
            : row.totalDisplayWidth(zoom: 1.0)
        let width = baseWidth * zoom
        let height = row.displayHeight(zoom: 1.0) * zoom
        let label: LocalizedStringKey = isPreviewMode ? "Rendering preview…" : "Loading editor…"

        ZStack {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: width, height: height)
        .task {
            // Yield so SwiftUI has a chance to paint this placeholder before
            // the (potentially expensive) target view body kicks in.
            try? await Task.sleep(for: .milliseconds(50))
            modeReady = true
        }
    }

    /// Lazy: each bar carries two alert hosts, a popover host and an AppKit `Menu`, and a wide row
    /// can have twenty of them — all of which used to build the moment the row was realized.
    /// Height is pinned so the row doesn't resize as bars scroll in; the eager canvas `HStack`
    /// above still pins the scroll content's width.
    ///
    /// Both axes are stated on each child as well, so the stack works out which indices are visible
    /// without measuring anything — laziness gets cheaper, not eager. Pinning only the stack's
    /// height still left `LazyHVStack.lengthAndSpacing` proposing to each bar for its height, which
    /// a scrollbar-drag trace showed descending all the way into `ActionButton.body`.
    @ViewBuilder
    func canvasView(
        dw: CGFloat,
        dh: CGFloat,
        ds: CGFloat,
        resolvedShapes: [CanvasShapeModel]
    ) -> some View {
        let facts = selectionFacts(in: resolvedShapes)
        ZStack(alignment: .topLeading) {
            EditorRasterizedBackgroundView(
                row: row.localizingBackgroundImages(to: state.localeState.activeLocaleCode),
                screenshotImages: state.screenshotImages,
                displayScale: ds
            )

            RowCanvasShapeLayerView(
                row: row,
                shapes: resolvedShapes,
                displayScale: ds
            ) { baseShape, clipRect in
                let isInSelection = selectedShapeIds.contains(baseShape.id)
                let isMulti = isInSelection && selectedShapeIds.count > 1

                // Everything below reads the *live* shape, so a properties-bar slider drag
                // re-evaluates this one shape rather than the whole row. See `LiveShapeContent`.
                LiveShapeContent(baseShape: baseShape, session: state.liveShapeEdit) { shape in
                    let isCropping = state.imageCrop.shapeId == shape.id
                    CanvasShapeView(
                        shape: shape,
                        displayScale: ds,
                        // Canvas now renders at full scale (no outer `.scaleEffect`), so `zoom`
                        // is folded into `displayScale` here — pass 1.0 like the selection layer.
                        zoom: 1.0,
                        isSelected: isInSelection,
                        isMultiSelected: isMulti,
                        isCropping: isCropping,
                        screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                        screenshotImageIdentity: shape.displayImageFileName,
                        resourceState: CanvasResourceState(shape.displayImageFileName, in: state),
                        fillImage: shape.fillImageConfig?.fileName.flatMap { state.screenshotImages[$0] },
                        defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                        deviceModelRenderingMode: .snapshot,
                        clipBounds: clipRect,
                        showsEditorHelpers: !state.viewMode.isViewMode,
                        allowSynchronousSvgRender: false,
                        dragSession: dragSession,
                        availableFontFamilies: state.availableFontFamilySet,
                        contextMenuContent: { shapeContextMenu(for: shape, facts: facts, isCropping: isCropping) },
                        interactions: shapeInteractions(
                            for: shape, isInSelection: isInSelection, isMulti: isMulti, resolvedShapes: resolvedShapes
                        )
                    )
                }
            }

            CanvasHoverLayer(
                row: row,
                resolvedShapes: resolvedShapes,
                selectedShapeIds: selectedShapeIds,
                localeState: state.localeState,
                visualScale: ds,
                dragSession: dragSession,
                liveShapeEdit: state.liveShapeEdit
            )

            ActiveGuidesLayer(dragSession: dragSession, displayScale: ds)
                .zIndex(100)

            #if !os(macOS)
            imagePickerHost(anchor: imagePickerAnchor(in: resolvedShapes, displayScale: ds))
            #endif

            if row.showBorders && row.templates.count > 1 {
                CanvasTemplateSeparatorLines(
                    templateCount: row.templates.count,
                    templateDisplayWidth: dw,
                    templateDisplayHeight: dh
                )
            }

            // The first coach mark points at the center of the row's first template.
            // The popover must attach to the template-sized frame BEFORE .position —
            // .position fills the canvas, which would re-anchor to its full bounds.
            Color.clear
                .frame(width: dw, height: dh)
                .coachPopover(
                    step: .canvas,
                    coach: state.coach,
                    isActive: isFirst && !isPreviewMode,
                    arrowEdge: .top,
                    attachmentAnchor: .point(.center)
                )
                .position(x: dw / 2, y: dh / 2)
                .allowsHitTesting(false)
        }
        .frame(
            width: dw * CGFloat(row.templates.count),
            height: dh,
            alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        // Owns both the empty-canvas click (select the row) and drag-to-select; see the modifier
        // for why they must share one gesture.
        .canvasBackgroundGesture(
            row: row,
            shapes: resolvedShapes,
            displayScale: ds,
            dragSession: dragSession,
            liveShapeEdit: state.liveShapeEdit,
            existingSelection: selectedShapeIds,
            isEnabled: !state.viewMode.isViewMode,
            onSelect: { ids in
                // A sweep is a fresh interaction, like the click it replaces: hand focus back from
                // any field editor so Delete and the arrow keys reach the canvas.
                resignFieldEditor()
                state.selectShapes(ids, in: row.id)
            },
            onTapEmptyCanvas: { tapSelectRow() }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let modelPoint = CGPoint(
                    x: location.x / ds,
                    y: location.y / ds
                )
                state.canvasHints.mouseModelPosition = modelPoint
                // Keep right-click position up-to-date while hovering,
                // so it reflects cursor position when context menu opens.
                contextMenuPointStore.value = modelPoint
                updateHover(at: modelPoint, in: resolvedShapes)
            case .ended:
                state.canvasHints.mouseModelPosition = nil
                clearHover()
            @unknown default:
                break
            }
        }
        .onDrop(of: [.image, .svg, .fileURL], isTargeted: nil) { providers, location in
            handleCanvasDrop(providers, at: location, displayScale: ds)
        }
    }
}
