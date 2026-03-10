import SwiftUI
import UniformTypeIdentifiers

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    @State private var isDeletingRow = false
    @State private var isRowHovered = false
    @State private var activeGuides: [AlignmentGuide] = []

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row header
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? .blue : .gray.opacity(0.4))
                    .frame(width: 6, height: 6)

                Text(row.label)
                    .font(.system(size: 12, weight: .medium))

                Text(verbatim: row.resolutionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 4) {
                    rowActionButton("chevron.up", tooltip: "Move up", disabled: !canMoveUp) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
                    }
                    rowActionButton("chevron.down", tooltip: "Move down", disabled: !canMoveDown) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
                    }
                    rowActionButton("doc.on.doc", tooltip: "Duplicate row", disabled: false) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
                    }
                    rowActionButton("trash", tooltip: "Delete row", disabled: !canDelete, isDestructive: true) {
                        isDeletingRow = true
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
                    ZStack(alignment: .topLeading) {
                        // Background tiles (one per template, no gap)
                        HStack(spacing: 0) {
                            ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, _ in
                                row.effectiveBackgroundFill(forTemplateAt: index)
                                    .frame(width: dw, height: dh)
                            }
                        }

                        // Shared shapes layer (resolved for active locale)
                        ForEach(LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)) { shape in
                            let shapeView = CanvasShapeView(
                                shape: shape,
                                displayScale: ds,
                                isSelected: shape.id == state.selectedShapeId,
                                screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                                onSelect: { state.selectShape(shape.id, in: row.id) },
                                onUpdate: { state.updateShape($0) },
                                onDelete: { state.deleteShape(shape.id) },
                                onScreenshotDrop: (shape.type == .device || shape.type == .image) ? { image in
                                    state.saveImage(image, for: shape.id)
                                } : nil,
                                onDragSnap: { draggedShape, rawOffset in
                                    let others = row.activeShapes.filter { $0.id != draggedShape.id }
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
                                }
                            )

                            if shape.clipToTemplate == true {
                                let ti = row.owningTemplateIndex(for: shape)
                                shapeView
                                    .mask {
                                        Rectangle()
                                            .frame(width: dw, height: dh)
                                            .position(x: CGFloat(ti) * dw + dw / 2, y: dh / 2)
                                    }
                            } else {
                                shapeView
                            }
                        }

                        // Alignment guide lines
                        ForEach(activeGuides) { guide in
                            AlignmentGuideLineView(guide: guide, displayScale: ds)
                        }
                        .zIndex(100)

                        // Guideline separators (always on top)
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
                        height: dh
                    )
                    .clipped()
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { tapSelectRow() }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            state.canvasMouseModelPosition = CGPoint(
                                x: location.x / ds,
                                y: location.y / ds
                            )
                        case .ended:
                            state.canvasMouseModelPosition = nil
                        @unknown default:
                            break
                        }
                    }
                    .onDrop(of: [.image, .svg], delegate: CanvasDropDelegate(
                        onDrop: { providers, location in
                            handleCanvasDrop(providers, at: location, displayScale: ds)
                        }
                    ))

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
                            onSave: { state.scheduleSave() },
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
        .contentShape(Rectangle())
        .onTapGesture { tapSelectRow() }
        .background(isSelected ? Color.accentColor.opacity(0.04) : Color.clear)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .allowsHitTesting(false)
            }
        }
        .contextMenu {
            Button("Add Screenshot") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.addTemplate(to: row.id)
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
            Button("Delete Row", role: .destructive) {
                isDeletingRow = true
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
    }

    private func handleCanvasDrop(_ providers: [NSItemProvider], at displayLocation: CGPoint, displayScale ds: CGFloat) -> Bool {
        guard let provider = providers.first else { return false }
        let modelX = displayLocation.x / ds
        let modelY = displayLocation.y / ds

        // Try SVG file first
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
            return true
        }

        // Fall back to image
        provider.loadObject(ofClass: NSImage.self) { image, _ in
            guard let image = image as? NSImage else { return }
            DispatchQueue.main.async {
                state.selectRow(row.id)
                let imgW = image.size.width
                let imgH = image.size.height
                let maxW = row.templateWidth * 0.8
                let maxH = row.templateHeight * 0.8
                let scale = min(maxW / imgW, maxH / imgH, 1.0)
                let w = imgW * scale
                let h = imgH * scale
                let shape = CanvasShapeModel(
                    type: .image,
                    x: modelX - w / 2,
                    y: modelY - h / 2,
                    width: w,
                    height: h,
                    color: .clear
                )
                state.addShape(shape)
                state.saveImage(image, for: shape.id)
            }
        }
        return true
    }

    private func tapSelectRow() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        state.selectRow(row.id)
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

    private func rowActionButton(
        _ icon: String,
        tooltip: String,
        disabled: Bool,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(
            disabled
            ? AnyShapeStyle(.tertiary)
            : (isDestructive ? AnyShapeStyle(Color.red.opacity(0.8)) : AnyShapeStyle(.secondary))
        )
        .disabled(disabled)
        .help(tooltip)
    }
}

private struct CanvasDropDelegate: DropDelegate {
    let onDrop: ([NSItemProvider], CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.image, .svg])
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.svg]) + info.itemProviders(for: [.image])
        guard !providers.isEmpty else { return false }
        return onDrop(providers, info.location)
    }
}
