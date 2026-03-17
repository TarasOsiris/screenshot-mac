import SwiftUI
import UniformTypeIdentifiers

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @State private var isDeletingRow = false
    @State private var isResettingRow = false
    @State private var isRowHovered = false
    @State private var isSvgDialogPresented = false
    @State private var rightClickModelPoint: CGPoint?
    @State private var activeGuides: [AlignmentGuide] = []
    @State private var isEditingLabel = false
    @State private var editingLabelText = ""
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
            // Row header
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.accentColor : .gray.opacity(0.4))
                    .frame(width: isSelected ? 7 : 6, height: isSelected ? 7 : 6)

                if isEditingLabel {
                    TextField("Row label", text: $editingLabelText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 60, maxWidth: 200)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(4)
                        .focused($isLabelFieldFocused)
                        .onSubmit { commitLabelEdit() }
                        .onChange(of: isLabelFieldFocused) {
                            if !isLabelFieldFocused { commitLabelEdit() }
                        }
                        .onExitCommand { cancelLabelEdit() }
                } else {
                    Text(row.label.isEmpty ? "Untitled Row" : row.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : .secondary)
                        .opacity(row.label.isEmpty ? 0.5 : 1)
                        .onTapGesture(count: 2) { startLabelEdit() }
                }

                Text(verbatim: row.resolutionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    ActionButton(icon: "chevron.up", tooltip: "Move up", disabled: !canMoveUp) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
                    }
                    ActionButton(icon: "chevron.down", tooltip: "Move down", disabled: !canMoveDown) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
                    }
                    ActionButton(icon: "doc.on.doc", tooltip: "Duplicate row", disabled: false) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
                    }
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset row", isDestructive: true, disabled: false) {
                        if confirmBeforeDeleting {
                            isResettingRow = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
                        }
                    }
                    ActionButton(icon: "trash", tooltip: "Delete row", isDestructive: true, disabled: !canDelete) {
                        if confirmBeforeDeleting {
                            isDeletingRow = true
                        } else {
                            withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
                        }
                    }
                }
                .opacity(isSelected || isRowHovered ? 1 : 0.65)
                .animation(.easeInOut(duration: 0.15), value: isSelected || isRowHovered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onHover { isRowHovered = $0 }

            // Unified canvas + add button
            ScrollView(.horizontal, showsIndicators: true) {
                let dw = row.displayWidth(zoom: zoom)
                let dh = row.displayHeight(zoom: zoom)
                let ds = row.displayScale(zoom: zoom)

                VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    // Unified canvas
                    canvasView(dw: dw, dh: dh, ds: ds)

                    // Add button
                    AddTemplateButton(width: dw, height: dh) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addTemplate(to: row.id)
                        }
                    }
                }

                // Per-template control bars (inside same ScrollView)
                HStack(spacing: 0) {
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                        if index > 0 {
                            Divider()
                                .frame(height: 20)
                        }
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
                            onDuplicate: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.duplicateTemplate(template.id, in: row.id)
                                }
                            },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.removeTemplate(template.id, from: row.id)
                                }
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
        .onScrollGeometryChange(for: CGRect.self) { geo in
            geo.visibleRect
        } action: { _, visibleRect in
            guard isSelected else { return }
            let ds = row.displayScale(zoom: zoom)
            let canvasX = max(0, visibleRect.midX - canvasHorizontalPadding)
            state.visibleCanvasModelCenter = CGPoint(
                x: canvasX / ds,
                y: row.templateHeight / 2
            )
        }
        .contentShape(Rectangle())
        .onTapGesture { tapSelectRow() }
        .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button("Add Screenshot") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.addTemplate(to: row.id)
                }
            }
            Menu("Add Element") {
                ForEach(ShapeType.allCases, id: \.self) { type in
                    Button {
                        if type == .svg {
                            state.selectRow(row.id)
                            isSvgDialogPresented = true
                        } else {
                            addShapeFromMenu(type)
                        }
                    } label: {
                        Label(type.label, systemImage: type.icon)
                    }
                }
            }
            Divider()
            Button(row.showDevice ? "Hide Devices" : "Show Devices") {
                if let idx = state.rows.firstIndex(where: { $0.id == row.id }) {
                    state.rows[idx].showDevice.toggle()
                    state.scheduleSave()
                }
            }
            Button(row.showBorders ? "Hide Borders" : "Show Borders") {
                if let idx = state.rows.firstIndex(where: { $0.id == row.id }) {
                    state.rows[idx].showBorders.toggle()
                    state.scheduleSave()
                }
            }
            Divider()
            Button("Move Up") {
                withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
            }
            .disabled(!canMoveUp)
            Button("Move Down") {
                withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
            }
            .disabled(!canMoveDown)
            Button("Duplicate Row") {
                withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
            }
            Divider()
            Button("Reset Row", role: .destructive) {
                if confirmBeforeDeleting {
                    isResettingRow = true
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
                }
            }
            Button("Delete Row", role: .destructive) {
                if confirmBeforeDeleting {
                    isDeletingRow = true
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
                }
            }
            .disabled(!canDelete)
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
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size, useColor, color in
                let center = rightClickModelPoint ?? state.shapeCenter(for: row)
                let scaledSize = SvgHelper.scaledSize(size)
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
        let baseX = displayLocation.x / ds
        let baseY = displayLocation.y / ds
        let offset: CGFloat = 60 // stagger offset per item in model space
        var handled = false

        for (i, provider) in providers.enumerated() {
            let modelX = baseX + CGFloat(i) * offset
            let modelY = baseY + CGFloat(i) * offset

            if provider.hasItemConformingToTypeIdentifier(UTType.svg.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { url, _ in
                    guard let url = url,
                          let content = try? String(contentsOf: url, encoding: .utf8) else { return }
                    let sanitized = SvgHelper.sanitize(content)
                    guard let data = sanitized.data(using: .utf8),
                          let image = NSImage(data: data) else { return }
                    let size = SvgHelper.parseSize(sanitized, fallbackImage: image)
                    DispatchQueue.main.async {
                        state.selectRow(row.id)
                        let scaledSize = SvgHelper.scaledSize(size)
                        let shape = CanvasShapeModel.defaultSvg(
                            centerX: modelX, centerY: modelY,
                            svgContent: sanitized, size: scaledSize
                        )
                        state.addShape(shape)
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                    guard let url = url, let image = NSImage(contentsOf: url) else { return }
                    DispatchQueue.main.async {
                        self.createImageShape(image: image, modelX: modelX, modelY: modelY)
                    }
                }
                handled = true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                    guard let url = url,
                          let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                          let uttype = UTType(typeId),
                          uttype.conforms(to: .image),
                          let image = NSImage.fromSecurityScopedURL(url) else { return }
                    DispatchQueue.main.async {
                        self.createImageShape(image: image, modelX: modelX, modelY: modelY)
                    }
                }
                handled = true
            }
        }

        return handled
    }

    @ViewBuilder
    private func canvasView(dw: CGFloat, dh: CGFloat, ds: CGFloat) -> some View {
        let resolvedShapes = LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)
        ZStack(alignment: .topLeading) {
            backgroundLayer(dw: dw, dh: dh)

            // Shared shapes layer (resolved for active locale)
            ForEach(resolvedShapes) { shape in
                let clipRect: CGRect? = shape.clipToTemplate == true ? {
                    let ti = row.owningTemplateIndex(for: shape)
                    return CGRect(x: CGFloat(ti) * dw, y: 0, width: dw, height: dh)
                }() : nil

                CanvasShapeView(
                    shape: shape,
                    displayScale: ds,
                    isSelected: shape.id == state.selectedShapeId,
                    screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    clipBounds: clipRect,
                    onSelect: { state.selectShape(shape.id, in: row.id) },
                    onUpdate: { state.updateShape($0) },
                    onDelete: { state.deleteShape(shape.id) },
                    onScreenshotDrop: { image in
                        state.saveImage(image, for: shape.id)
                    },
                    onClearImage: {
                        state.clearImage(for: shape.id)
                    },
                    onDragSnap: { draggedShape, rawOffset in
                        let others = resolvedShapes.filter { $0.id != draggedShape.id }
                        let threshold = 4 / ds
                        let result = AlignmentService.computeSnap(
                            draggedShape: draggedShape,
                            dragOffset: rawOffset,
                            otherShapes: others,
                            templateWidth: row.templateWidth,
                            templateHeight: row.templateHeight,
                            templateCount: row.templates.count,
                            snapThreshold: threshold
                        )
                        activeGuides = result.guides
                        return result
                    },
                    onDragEnd: { activeGuides = [] },
                    onOptionDragDuplicate: { shapeId in
                        state.duplicateShapeForOptionDrag(shapeId)
                    },
                    onDidAppearAfterAdd: shape.id == state.justAddedShapeId ? { state.justAddedShapeId = nil } : nil
                )
            }

            // Alignment guide lines
            ForEach(activeGuides) { guide in
                AlignmentGuideLineView(guide: guide, displayScale: ds)
            }
            .zIndex(100)

            // Guideline separators
            if row.showBorders && row.templates.count > 1 {
                ForEach(1..<row.templates.count, id: \.self) { i in
                    ZStack {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 0, y: dh))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.black)

                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0))
                            path.addLine(to: CGPoint(x: 0, y: dh))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4], dashPhase: 4))
                        .foregroundStyle(.white)
                    }
                    .frame(width: 1, height: dh)
                    .offset(x: dw * CGFloat(i))
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(
            width: row.totalDisplayWidth(zoom: zoom),
            height: dh,
            alignment: .topLeading
        )
        .clipped()
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
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
                rightClickModelPoint = modelPoint
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

    @ViewBuilder
    private func backgroundLayer(dw: CGFloat, dh: CGFloat) -> some View {
        let templateModelSize = CGSize(width: row.templateWidth, height: row.templateHeight)
        if row.isSpanningBackground {
            let totalWidth = dw * CGFloat(row.templates.count)
            let spanModelSize = CGSize(width: row.templateWidth * CGFloat(row.templates.count), height: row.templateHeight)
            ZStack(alignment: .topLeading) {
                row.resolvedBackgroundView(screenshotImages: state.screenshotImages, modelSize: spanModelSize)
                    .frame(width: totalWidth, height: dh)
                HStack(spacing: 0) {
                    ForEach(row.templates) { template in
                        if template.overrideBackground {
                            template.resolvedBackgroundView(screenshotImages: state.screenshotImages, modelSize: templateModelSize)
                                .frame(width: dw, height: dh)
                        } else {
                            Color.clear.frame(width: dw, height: dh)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 0) {
                ForEach(row.templates) { template in
                    if template.overrideBackground {
                        template.resolvedBackgroundView(screenshotImages: state.screenshotImages, modelSize: templateModelSize)
                            .frame(width: dw, height: dh)
                    } else {
                        row.resolvedBackgroundView(screenshotImages: state.screenshotImages, modelSize: templateModelSize)
                            .frame(width: dw, height: dh)
                    }
                }
            }
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
                state.rows[ri].templates[templateIndex] = newValue
            }
        )
    }

    // MARK: - Add Element helpers

    private func addShapeFromMenu(_ type: ShapeType) {
        let center = rightClickModelPoint ?? state.shapeCenter(for: row)
        state.selectRow(row.id)
        guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: center.x, centerY: center.y) else { return }
        state.addShape(shape)
    }

}
