import SwiftUI
import UniformTypeIdentifiers

extension EditorRowView {
    @ViewBuilder
    var horizontalScrollArea: some View {
        ScrollViewReader { hProxy in
            ScrollView(.horizontal, showsIndicators: true) {
                // Render the canvas at full (zoom-inclusive) scale instead of a visual-only
                // `.scaleEffect(zoom)`. Each shape's layout frame then equals its on-screen
                // size, which the iOS context-menu lift anchors to — a presentation-only zoom
                // transform makes the lift mis-scale (shrink on press, snap back on dismiss).
                let dw = row.displayWidth(zoom: zoom)
                let dh = row.displayHeight(zoom: zoom)
                let ds = row.displayScale(zoom: zoom)

                let resolved = LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)

                VStack(alignment: .leading, spacing: 0) {
                    if !modeReady {
                        modeLoadingPlaceholder
                    } else if isPreviewMode {
                        RowPreviewView(state: state, row: row, zoom: zoom)
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            // Unified canvas with per-template scroll anchors. Rendered at
                            // full scale (no `.scaleEffect`) so shape layout frames match
                            // their on-screen size; the selection layer renders the same way.
                            ZStack(alignment: .topLeading) {
                                canvasView(dw: dw, dh: dh, ds: ds, resolvedShapes: resolved)
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

                                CanvasSelectionLayer(
                                    state: state,
                                    row: row,
                                    resolvedShapes: resolved,
                                    visualScale: ds,
                                    pendingResize: $pendingResize,
                                    pendingRotation: $pendingRotation,
                                    textEditingShapeId: textEditingShapeId,
                                    activeDragOffset: activeDragOffset,
                                    draggingShapeId: draggingShapeId
                                )
                                .frame(
                                    width: row.totalDisplayWidth(zoom: zoom),
                                    height: row.displayHeight(zoom: zoom),
                                    alignment: .topLeading
                                )
                            }

                            AddTemplateButton(width: row.displayWidth(zoom: zoom), height: row.displayHeight(zoom: zoom)) {
                                store.requirePro(
                                    allowed: store.canAddTemplate(currentCount: row.templates.count),
                                    context: .templateLimit
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        state.addTemplate(to: row.id)
                                    }
                                }
                            }
                        }

                        controlBarsRow
                            .padding(.bottom, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .onChange(of: state.focusRequestNonce) { _, _ in
                guard state.selectedRowId == row.id,
                      let shapeId = state.focusShapeId,
                      let shape = row.shapes.first(where: { $0.id == shapeId }) else { return }
                let templateIndex = row.owningTemplateIndex(for: shape)
                guard templateIndex < row.templates.count else { return }
                let templateId = row.templates[templateIndex].id
                hProxy.scrollTo("focus_\(templateId)", anchor: .center)
                state.focusShapeId = nil
            }
        }
    }

    @ViewBuilder
    var modeLoadingPlaceholder: some View {
        let n = CGFloat(row.templates.count)
        let tileGap: CGFloat = 12
        // Match whichever mode we're about to render so layout doesn't jump.
        let baseWidth = isPreviewMode
            ? row.displayWidth(zoom: 1.0) * n + tileGap * max(0, n - 1)
            : row.totalDisplayWidth(zoom: 1.0)
        let width = baseWidth * zoom
        let height = row.displayHeight(zoom: 1.0) * zoom
        let label = isPreviewMode ? "Rendering preview…" : "Loading editor…"

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

    @ViewBuilder
    var controlBarsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                TemplateControlBar(
                    template: safeTemplateBinding(rowId: row.id, templateIndex: index),
                    row: row,
                    index: index,
                    zoom: zoom,
                    screenshotImages: state.screenshotImages,
                    localeState: state.localeState,
                    canMoveLeft: index > 0,
                    canMoveRight: index < row.templates.count - 1,
                    onMoveLeft: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.moveTemplateLeft(template.id, in: row.id)
                        }
                    },
                    onMoveRight: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.moveTemplateRight(template.id, in: row.id)
                        }
                    },
                    onSave: { state.scheduleSave() },
                    // macOS file-panel path; on iPad BackgroundImageEditor picks via ImageSourceMenu
                    // and saves through onDropBackgroundImage below.
                    onPickBackgroundImage: { state.pickAndSaveBackgroundImage(for: row.id, templateIndex: index) },
                    onRemoveBackgroundImage: { state.removeBackgroundImage(for: row.id, templateIndex: index) },
                    onDropBackgroundImage: { image in
                        state.saveBackgroundImage(image, for: row.id, templateIndex: index)
                    },
                    onDropBackgroundSvg: { svgContent in
                        state.saveBackgroundSvg(svgContent, for: row.id, templateIndex: index)
                    },
                    onDuplicate: {
                        store.requirePro(
                            allowed: store.canAddTemplate(currentCount: row.templates.count),
                            context: .templateLimit
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.duplicateTemplate(template.id, in: row.id)
                            }
                        }
                    },
                    onDuplicateToEnd: {
                        store.requirePro(
                            allowed: store.canAddTemplate(currentCount: row.templates.count),
                            context: .templateLimit
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.duplicateTemplateToEnd(template.id, in: row.id)
                            }
                        }
                    },
                    onInsertBefore: {
                        store.requirePro(
                            allowed: store.canAddTemplate(currentCount: row.templates.count),
                            context: .templateLimit
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.insertTemplateBefore(template.id, in: row.id)
                            }
                        }
                    },
                    onInsertAfter: {
                        store.requirePro(
                            allowed: store.canAddTemplate(currentCount: row.templates.count),
                            context: .templateLimit
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.insertTemplateAfter(template.id, in: row.id)
                            }
                        }
                    },
                    onDelete: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.removeTemplate(template.id, from: row.id)
                        }
                    },
                    onLoadFullResImages: { [weak state] in
                        guard let state else { return [:] }
                        return state.loadFullResolutionImages(forRow: row, localeCode: state.localeState.activeLocaleCode)
                    }
                )
            }
        }
    }

    @ViewBuilder
    func canvasView(dw: CGFloat, dh: CGFloat, ds: CGFloat, resolvedShapes: [CanvasShapeModel]) -> some View {
        let selectedShapeIds = state.selectedShapeIds
        let isNonBaseLocale = !state.localeState.isBaseLocale
        let currentLocaleName: String? = isNonBaseLocale ? state.localeState.activeLocaleLabel : nil
        let nonBaseLocaleCount = state.localeState.nonBaseLocaleCount
        // Computed once per render — the per-shape closure below references it
        // instead of recomputing the O(N) walk for every shape's `lockToggleWillUnlock`.
        let selectionFullyLocked = state.isSelectionFullyLocked
        let allSelectedSameType: Bool = selectedShapeIds.count > 1 && {
            var firstType: ShapeType?
            for shape in resolvedShapes where selectedShapeIds.contains(shape.id) {
                if let ft = firstType {
                    if shape.type != ft { return false }
                } else {
                    firstType = shape.type
                }
            }
            return firstType != nil
        }()
        ZStack(alignment: .topLeading) {
            EditorRasterizedBackgroundView(
                row: row,
                screenshotImages: state.screenshotImages,
                displayScale: ds
            )

            RowCanvasShapeLayerView(
                row: row,
                shapes: resolvedShapes,
                displayScale: ds
            ) { shape, clipRect in
                let isInSelection = selectedShapeIds.contains(shape.id)
                let isMulti = isInSelection && selectedShapeIds.count > 1
                // Locked shapes don't follow a group drag visually either —
                // `applyGroupDrag` already skips them at commit time, so without
                // this guard the locked shape would slide with the cursor and
                // then snap back when the drag ends.
                let isFollowingDrag = isMulti && draggingShapeId != nil && draggingShapeId != shape.id && !shape.resolvedIsLocked
                let groupOffset: CGSize = isFollowingDrag ? activeDragOffset : .zero

                CanvasShapeView(
                    shape: shape,
                    displayScale: ds,
                    // Canvas now renders at full scale (no outer `.scaleEffect`), so `zoom`
                    // is folded into `displayScale` here — pass 1.0 like the selection layer.
                    zoom: 1.0,
                    isSelected: isInSelection,
                    isMultiSelected: isMulti,
                    screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                    fillImage: shape.fillImageConfig?.fileName.flatMap { state.screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    groupDragOffset: groupOffset,
                    deviceModelRenderingMode: .snapshot,
                    clipBounds: clipRect,
                    resizeState: pendingResize[shape.id],
                    rotationDelta: pendingRotation[shape.id] ?? 0,
                    onSelect: { state.selectShape(shape.id, in: row.id) },
                    onShiftSelect: { state.toggleShapeSelection(shape.id, in: row.id) },
                    onUpdate: { state.updateShape($0) },
                    onDelete: { state.deleteShape(shape.id) },
                    onScreenshotDrop: { image in
                        state.saveImage(image, for: shape.id)
                    },
                    onClearImage: {
                        state.clearImage(for: shape.id)
                    },
                    onRemoveBackground: shape.type == .image ? {
                        state.removeImageBackground(for: shape.id) { message in
                            backgroundRemovalError = message
                        }
                    } : nil,
                    onCaptureSimulator: simulatorCaptureAction(for: shape),
                    onDragSnap: { draggedShape, rawOffset in
                        let targets: [AlignmentService.OtherShapeBounds]
                        if let cached = cachedSnapTargets {
                            targets = cached
                        } else if isInSelection {
                            let filtered = AlignmentService.makeSnapTargets(
                                from: resolvedShapes.filter { !selectedShapeIds.contains($0.id) }
                            )
                            cachedSnapTargets = filtered
                            targets = filtered
                        } else {
                            let filtered = AlignmentService.makeSnapTargets(
                                from: resolvedShapes.filter { $0.id != draggedShape.id }
                            )
                            cachedSnapTargets = filtered
                            targets = filtered
                        }
                        let threshold = 4 / row.displayScale(zoom: zoom)
                        let result = AlignmentService.computeSnap(
                            draggedShape: draggedShape,
                            dragOffset: rawOffset,
                            otherShapeBounds: targets,
                            templateWidth: row.templateWidth,
                            templateHeight: row.templateHeight,
                            templateCount: row.templates.count,
                            snapThreshold: threshold
                        )
                        if activeGuides != result.guides {
                            activeGuides = result.guides
                        }
                        return result
                    },
                    onDragEnd: {
                        activeGuides = []
                        activeDragOffset = .zero
                        draggingShapeId = nil
                        cachedSnapTargets = nil
                    },
                    onOptionDragDuplicate: { shapeId in
                        if isMulti {
                            state.duplicateShapesForOptionDrag()
                            return nil
                        }
                        return state.duplicateShapeForOptionDrag(shapeId)
                    },
                    onDragProgress: { offset in
                        draggingShapeId = shape.id
                        activeDragOffset = offset
                    },
                    onGroupDragEnd: { offset in
                        state.applyGroupDrag(offset: offset)
                        activeDragOffset = .zero
                        draggingShapeId = nil
                        cachedSnapTargets = nil
                    },
                    onDidAppearAfterAdd: shape.id == state.justAddedShapeId ? { state.justAddedShapeId = nil } : nil,
                    onEditingTextChanged: { editing in
                        if state.isEditingText != editing { state.isEditingText = editing }
                        if editing {
                            if textEditingShapeId != shape.id { textEditingShapeId = shape.id }
                        } else if textEditingShapeId == shape.id {
                            textEditingShapeId = nil
                        }
                    },
                    onFormatBarStateChanged: { selState, controller in
                        state.richTextSelectionState = selState
                        state.richTextFormatController = controller
                    },
                    onFormatBarAnchorChanged: { anchor in
                        state.richTextFormatBarAnchor = anchor
                    },
                    onMatchDeviceSizes: shape.type == .device ? {
                        let matchingIds = Set(row.activeShapes.filter { other in
                            other.id != shape.id &&
                            other.type == .device &&
                            other.deviceCategory == shape.deviceCategory
                        }.map(\.id))
                        guard !matchingIds.isEmpty else { return }
                        state.updateShapes(matchingIds, in: row.id) { other in
                            other.width = shape.width
                            other.height = shape.height
                        }
                    } : nil,
                    onMatchSelectedDeviceSizes: {
                        guard isMulti,
                              shape.type == .device,
                              selectedShapeIds.contains(shape.id) else { return nil }
                        let selectedDeviceIds = row.activeShapes.compactMap {
                            (selectedShapeIds.contains($0.id) && $0.type == .device) ? $0.id : nil
                        }
                        guard selectedDeviceIds.count == selectedShapeIds.count else { return nil }
                        let targetIds = Set(selectedDeviceIds.filter { $0 != shape.id })
                        guard !targetIds.isEmpty else { return nil }
                        return {
                            state.updateShapes(targetIds,
                                               in: row.id,
                                               undoName: "Match Size to Selected Devices") { other in
                                other.width = shape.width
                                other.height = shape.height
                            }
                        }
                    }(),
                    onCenterDevice: shape.type == .device ? { axis in
                        let isMultiDeviceSelection = isMulti
                            && selectedShapeIds.contains(shape.id)
                            && row.activeShapes.allSatisfy {
                                !selectedShapeIds.contains($0.id) || $0.type == .device
                            }
                        let targets: Set<UUID> = isMultiDeviceSelection ? selectedShapeIds : [shape.id]
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.centerDevices(targets, in: row.id, axis: axis)
                        }
                    } : nil,
                    onTranslate: (shape.type == .text && isNonBaseLocale) ? {
                        state.pendingTranslateShapeId = shape.id
                    } : nil,
                    translateLocaleName: currentLocaleName,
                    onTranslateAllLocales: (shape.type == .text && !isNonBaseLocale && nonBaseLocaleCount > 0) ? {
                        let isMultiText = selectedShapeIds.count > 1 && selectedShapeIds.contains(shape.id)
                        if isMultiText {
                            let translatableIds: Set<UUID> = Set(
                                row.activeShapes
                                    .filter { selectedShapeIds.contains($0.id) && $0.hasTranslatableText }
                                    .map(\.id)
                            )
                            guard !translatableIds.isEmpty else { return }
                            state.pendingFanOutTranslateShapeIds = translatableIds
                        } else {
                            state.pendingFanOutTranslateShapeIds = [shape.id]
                        }
                    } : nil,
                    translateAllLocalesDisabled: state.isFanOutTranslating,
                    nonBaseLocaleCount: nonBaseLocaleCount,
                    onCopyTextStyle: shape.type == .text ? {
                        state.textStyleClipboard = shape.extractTextStyle()
                    } : nil,
                    onPasteTextStyle: shape.type == .text && state.textStyleClipboard != nil ? { [rowId = row.id] in
                        guard let style = state.textStyleClipboard else { return }
                        state.updateShapes([shape.id], in: rowId) { $0.applyTextStyle(style) }
                    } : nil,
                    availableFontFamilies: state.availableFontFamilySet,
                    onUpdateSelected: isMulti && allSelectedSameType ? { update in
                        state.updateShapes(selectedShapeIds, in: row.id, update: update)
                    } : nil,
                    onDeleteSelected: isMulti ? {
                        state.deleteSelectedShapes()
                    } : nil,
                    onAlignSelected: isMulti ? { alignment in
                        state.alignSelectedShapes(alignment)
                    } : nil,
                    onDuplicateToTemplates: row.templates.count > 1 ? { [shapeId = shape.id] direction in
                        let ids = state.selectedShapeIds.isEmpty ? [shapeId] : state.selectedShapeIds
                        state.duplicateShapesToTemplates(Set(ids), direction: direction)
                    } : nil,
                    onToggleLock: { [shapeId = shape.id] in
                        if !state.selectedShapeIds.contains(shapeId) {
                            state.selectShape(shapeId, in: row.id)
                        }
                        state.toggleLockOnSelection()
                    },
                    lockToggleWillUnlock: isInSelection ? selectionFullyLocked : shape.resolvedIsLocked
                )
            }

            ForEach(activeGuides) { guide in
                AlignmentGuideLineView(guide: guide, displayScale: ds)
            }
            .zIndex(100)

            if row.showBorders && row.templates.count > 1 {
                CanvasTemplateSeparatorLines(
                    templateCount: row.templates.count,
                    templateDisplayWidth: dw,
                    templateDisplayHeight: dh
                )
            }
        }
        .frame(
            width: dw * CGFloat(row.templates.count),
            height: dh,
            alignment: .topLeading
        )
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { tapSelectRow() }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let modelPoint = CGPoint(
                    x: location.x / ds,
                    y: location.y / ds
                )
                state.canvasMouseModelPosition = modelPoint
                // Keep right-click position up-to-date while hovering,
                // so it reflects cursor position when context menu opens.
                contextMenuPointStore.value = modelPoint
            case .ended:
                state.canvasMouseModelPosition = nil
            @unknown default:
                break
            }
        }
        .onDrop(of: [.image, .svg, .fileURL], isTargeted: nil) { providers, location in
            handleCanvasDrop(providers, at: location, displayScale: ds)
        }
    }
}
