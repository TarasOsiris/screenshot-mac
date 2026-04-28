import SwiftUI
import UniformTypeIdentifiers

private final class ModelPointStore {
    var value: CGPoint?
}

struct EditorRowView: View {
    @Bindable var state: AppState
    @Environment(StoreService.self) private var store
    let row: ScreenshotRow
    let requestShowcaseExport: (ScreenshotRow) -> Void
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @State private var isDeletingRow = false
    @State private var isResettingRow = false
    @State private var isSvgDialogPresented = false
    @State private var contextMenuPointStore = ModelPointStore()
    @State private var activeGuides: [AlignmentGuide] = []
    @State private var activeDragOffset: CGSize = .zero
    @State private var draggingShapeId: UUID?
    @State private var canvasGlobalOrigin: CGPoint = .zero
    @State private var isEditingLabel = false
    @State private var editingLabelText = ""
    @State private var exportError: String?
    @State private var simulatorCaptureError: String?
    @State private var simulatorInstallPromptShapeId: UUID?
    /// Cached snap targets for non-selected shapes during drag.
    @State private var cachedSnapTargets: [AlignmentService.OtherShapeBounds]?
    @FocusState private var isLabelFieldFocused: Bool

    private var isSelected: Bool {
        state.selectedRowId == row.id
    }

    private var canMoveUp: Bool {
        state.rows.first?.id != row.id
    }

    private var canMoveDown: Bool {
        state.rows.last?.id != row.id
    }

    private var canDelete: Bool {
        state.rows.count > 1
    }

    private var zoom: CGFloat { state.zoomLevel }
    private let canvasHorizontalPadding: CGFloat = 16

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
                    withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
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
                }
            ) {
                rowMenuContent
            }

            // Unified canvas + add button
            if !row.isCollapsed {
                horizontalScrollArea
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
        .contextMenu {
            rowMenuContent
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
        .alert("iOS Simulator Capture Failed", isPresented: $simulatorCaptureError.isPresent()) {
            Button("OK") { simulatorCaptureError = nil }
        } message: {
            Text(simulatorCaptureError ?? "")
        }
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

    private func handleCanvasDrop(_ providers: [NSItemProvider], at displayLocation: CGPoint, displayScale ds: CGFloat) -> Bool {
        guard !providers.isEmpty else { return false }

        // Separate SVG providers from image providers
        var svgProviders: [NSItemProvider] = []
        var imageProviders: [NSItemProvider] = []
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.svg.identifier) {
                svgProviders.append(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) ||
                      provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                imageProviders.append(provider)
            }
        }

        var handled = false
        let baseX = displayLocation.x / ds
        let baseY = displayLocation.y / ds

        // Handle SVGs with stagger behavior
        for (i, provider) in svgProviders.enumerated() {
            let modelX = baseX + CGFloat(i) * 60
            let modelY = baseY + CGFloat(i) * 60
            provider.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { url, _ in
                guard let url = url,
                      let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                let sanitized = SvgHelper.sanitize(content)
                guard let data = sanitized.data(using: .utf8),
                      let image = NSImage(data: data) else { return }
                let size = SvgHelper.parseSize(sanitized, fallbackImage: image)
                DispatchQueue.main.async {
                    state.selectRow(row.id)
                    let maxDim = row.svgMaxDimension
                    let scaledSize = SvgHelper.scaledSize(size, maxDim: maxDim)
                    let shape = CanvasShapeModel.defaultSvg(
                        centerX: modelX, centerY: modelY,
                        svgContent: sanitized, size: scaledSize
                    )
                    state.addShape(shape)
                }
            }
            handled = true
        }

        // Handle image providers: batch = one per template, single = at drop location
        if imageProviders.count > 1 {
            handleBatchImageDrop(imageProviders)
            handled = true
        } else if let provider = imageProviders.first {
            let modelX = baseX
            let modelY = baseY
            ItemProviderImageLoader.loadImage(from: provider) { image in
                guard let image else { return }
                self.createImageShape(image: image, modelX: modelX, modelY: modelY)
            }
            handled = true
        }

        return handled
    }

    private func handleBatchImageDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        var loadedImages: [(Int, NSImage)] = []
        let lock = NSLock()

        for (i, provider) in providers.enumerated() {
            group.enter()
            ItemProviderImageLoader.loadImage(from: provider) { image in
                if let image {
                    lock.lock()
                    loadedImages.append((i, image))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [self] in
            let images = loadedImages.sorted(by: { $0.0 < $1.0 }).map(\.1)
            guard !images.isEmpty else { return }
            state.batchImportImages(images, into: row.id)
        }
    }

    @ViewBuilder
    private var horizontalScrollArea: some View {
        ScrollViewReader { hProxy in
            ScrollView(.horizontal, showsIndicators: true) {
                // Render canvas at base scale (zoom=1); apply zoom as a GPU transform
                let dw = row.displayWidth(zoom: 1.0)
                let dh = row.displayHeight(zoom: 1.0)
                let ds = row.displayScale(zoom: 1.0)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        // Unified canvas with per-template scroll anchors
                        canvasView(dw: dw, dh: dh, ds: ds)
                            .scaleEffect(zoom, anchor: .topLeading)
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

                        // Add button
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

                    // Per-template control bars (inside same ScrollView)
                    controlBarsRow
                        .padding(.bottom, 8)
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
    private var controlBarsRow: some View {
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
    private func canvasView(dw: CGFloat, dh: CGFloat, ds: CGFloat) -> some View {
        let resolvedShapes = LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)
        let selectedShapeIds = state.selectedShapeIds
        let isNonBaseLocale = !state.localeState.isBaseLocale
        let currentLocaleName: String? = isNonBaseLocale ? state.localeState.activeLocaleLabel : nil
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
                let groupOffset: CGSize = (isMulti && draggingShapeId != nil && draggingShapeId != shape.id) ? activeDragOffset : .zero

                CanvasShapeView(
                    shape: shape,
                    displayScale: ds,
                    zoom: zoom,
                    isSelected: isInSelection,
                    isMultiSelected: isMulti,
                    screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                    fillImage: shape.fillImageConfig?.fileName.flatMap { state.screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    groupDragOffset: groupOffset,
                    deviceModelRenderingMode: .snapshot,
                    clipBounds: clipRect,
                    canvasGlobalOrigin: canvasGlobalOrigin,
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
                    onCaptureSimulator: shape.type == .device ? {
                        if SimulatorCaptureService.isHelperInstalled {
                            state.captureFromSimulator(intoShape: shape.id) { message in
                                simulatorCaptureError = message
                            }
                        } else {
                            simulatorInstallPromptShapeId = shape.id
                        }
                    } : nil,
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
                            // Option+drag with multi-selection: duplicate all selected
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
                    onEditingTextChanged: { state.isEditingText = $0 },
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
                    onTranslate: (shape.type == .text && isNonBaseLocale) ? {
                        state.pendingTranslateShapeId = shape.id
                    } : nil,
                    translateLocaleName: currentLocaleName,
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
                    } : nil
                )
            }
            .onGeometryChange(for: CGPoint.self) { proxy in
                proxy.frame(in: .global).origin
            } action: { origin in
                canvasGlobalOrigin = origin
            }

            // Alignment guide lines
            ForEach(activeGuides) { guide in
                AlignmentGuideLineView(guide: guide, displayScale: ds)
            }
            .zIndex(100)

            // Guideline separators
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

    private func tapSelectRow() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        state.selectRow(row.id)
    }

    private func startLabelEdit() {
        editingLabelText = row.label
        isEditingLabel = true
        isLabelFieldFocused = true
    }

    private func commitLabelEdit() {
        guard isEditingLabel else { return }
        isEditingLabel = false
        state.updateRowLabel(row.id, text: editingLabelText)
    }

    private func cancelLabelEdit() {
        isEditingLabel = false
    }

    private func createImageShape(image: NSImage, modelX: CGFloat, modelY: CGFloat) {
        state.selectRow(row.id)
        state.addImageShape(image: image, centerX: modelX, centerY: modelY)
    }

    private static let placeholderTemplate = ScreenshotTemplate()

    private func safeTemplateBinding(rowId: UUID, templateIndex: Int) -> Binding<ScreenshotTemplate> {
        Binding(
            get: {
                guard let ri = state.rows.firstIndex(where: { $0.id == rowId }),
                      templateIndex < state.rows[ri].templates.count else {
                    return Self.placeholderTemplate
                }
                return state.rows[ri].templates[templateIndex]
            },
            set: { newValue in
                guard let ri = state.rows.firstIndex(where: { $0.id == rowId }),
                      templateIndex < state.rows[ri].templates.count else { return }
                state.registerUndoForRow(at: ri, "Edit Template")
                state.rows[ri].templates[templateIndex] = newValue
                state.scheduleSave()
            }
        )
    }

    // MARK: - Add Element helpers

    private func addShapeFromMenu(_ type: ShapeType) {
        let center = contextMenuPointStore.value ?? state.shapeCenter(for: row)
        state.selectRow(row.id)
        guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: center.x, centerY: center.y) else { return }
        state.addShape(shape)
    }

    // MARK: - Shared row menu

    @ViewBuilder
    private var rowMenuContent: some View {
        EditorRowMenuContent(
            state: state,
            row: row,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            canDelete: canDelete,
            confirmBeforeDeleting: confirmBeforeDeleting,
            isSvgDialogPresented: $isSvgDialogPresented,
            isResettingRow: $isResettingRow,
            isDeletingRow: $isDeletingRow,
            addShapeFromMenu: addShapeFromMenu,
            exportRowScreenshots: exportRowScreenshots,
            exportRowImage: { exportRowImage(showcase: $0) }
        )
    }

    private func exportRowScreenshots() {
        guard let folder = ExportFolderService.chooseFolder() else { return }
        let didAccess = folder.startAccessingSecurityScopedResource()

        Task { @MainActor in
            defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }

            do {
                let localeCode = state.localeState.activeLocaleCode
                let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
                let rowBackground = ExportService.renderComposedBackgroundImage(
                    row: row,
                    screenshotImages: images,
                    displayScale: 1.0,
                    labelPrefix: "row export"
                )

                try await withThrowingTaskGroup(of: Void.self) { group in
                    for index in row.templates.indices {
                        let image = ExportService.renderSingleTemplateImage(
                            index: index, row: row, screenshotImages: images,
                            localeCode: localeCode, localeState: state.localeState,
                            preRenderedRowBackground: rowBackground
                        )
                        let padded = String(format: "%02d", index + 1)
                        let fileURL = folder.appendingPathComponent("\(padded)_screenshot.png")
                        group.addTask {
                            guard let data = ExportService.encodeImage(image, format: .png) else {
                                throw ExportError.renderFailed
                            }
                            try data.write(to: fileURL)
                        }
                    }
                    try await group.waitForAll()
                }
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } catch {
                exportError = String(localized: "Could not export row screenshots: \(error.localizedDescription)")
            }
        }
    }

    private func exportRowImage(showcase: Bool) {
        if showcase {
            requestShowcaseExport(row)
            return
        }
        let localeCode = state.localeState.activeLocaleCode
        if let message = ExportService.saveRowImageViaPanel(defaultName: row.label, render: {
            let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
            return ExportService.renderRowImage(
                row: row, screenshotImages: images,
                localeCode: localeCode, localeState: state.localeState
            )
        }) {
            exportError = String(localized: "Could not export row image: \(message)")
        }
    }

}
