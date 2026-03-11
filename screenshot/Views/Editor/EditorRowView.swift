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
        guard !providers.isEmpty else { return false }
        let baseX = displayLocation.x / ds
        let baseY = displayLocation.y / ds
        let offset: CGFloat = 20 // stagger offset per item
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
        ZStack(alignment: .topLeading) {
            backgroundLayer(dw: dw, dh: dh)

            // Shared shapes layer (resolved for active locale)
            ForEach(LocaleService.resolveShapes(row.activeShapes, localeState: state.localeState)) { shape in
                let shapeView = CanvasShapeView(
                    shape: shape,
                    displayScale: ds,
                    isSelected: shape.id == state.selectedShapeId,
                    screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
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
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { _, template in
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
                ForEach(Array(row.templates.enumerated()), id: \.element.id) { _, template in
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

    private func createImageShape(image: NSImage, modelX: CGFloat, modelY: CGFloat) {
        state.selectRow(row.id)

        if Self.looksLikePhoneScreenshot(image) {
            let shape = CanvasShapeModel.defaultDevice(
                centerX: modelX, centerY: modelY,
                templateHeight: row.templateHeight
            )
            state.addShape(shape)
            state.saveImage(image, for: shape.id)
            return
        }

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

    // Known iPhone screenshot pixel sizes (portrait): "WxH"
    private static let knownPhoneScreenshotSizes: Set<String> = [
        "750x1334",   // iPhone SE / 8
        "828x1792",   // iPhone XR / 11
        "1080x1920",  // iPhone 6/7/8 Plus
        "1125x2436",  // iPhone X / XS / 11 Pro
        "1080x2340",  // iPhone 12 mini / 13 mini
        "1170x2532",  // iPhone 12 / 13 / 14
        "1179x2556",  // iPhone 14 Pro / 15 / 16
        "1206x2622",  // iPhone 16 Pro / 17 / 17 Pro
        "1260x2736",  // iPhone Air
        "1242x2688",  // iPhone XS Max / 11 Pro Max
        "1284x2778",  // iPhone 12/13 Pro Max
        "1290x2796",  // iPhone 14 Pro Max / 15 Pro Max / 16 Plus
        "1320x2868",  // iPhone 16 Pro Max / 17 Pro Max
    ]

    /// Heuristic: detect if an image looks like a phone screenshot.
    private static func looksLikePhoneScreenshot(_ image: NSImage) -> Bool {
        guard let rep = image.representations.first else { return false }
        let pw = rep.pixelsWide
        let ph = rep.pixelsHigh
        guard pw > 0, ph > 0, ph > pw else { return false }

        // Exact match against known iPhone resolutions
        if knownPhoneScreenshotSizes.contains("\(pw)x\(ph)") { return true }

        // General heuristic: portrait, phone-like width (640–1600px),
        // aspect ratio 16:9 (~1.78) to ~21.5:9 (~2.4) — covers most phones
        let ratio = CGFloat(ph) / CGFloat(pw)
        return pw >= 640 && pw <= 1600 && ratio >= 1.7 && ratio <= 2.4
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
