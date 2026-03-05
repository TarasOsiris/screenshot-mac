import SwiftUI
import UniformTypeIdentifiers

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    @State private var isDeletingRow = false

    private var isSelected: Bool {
        state.selectedRowId == row.id
    }

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
                    rowActionButton("chevron.up", disabled: state.rows.first?.id == row.id) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowUp(row.id) }
                    }
                    rowActionButton("chevron.down", disabled: state.rows.last?.id == row.id) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.moveRowDown(row.id) }
                    }
                    rowActionButton("doc.on.doc", disabled: false) {
                        withAnimation(.easeInOut(duration: 0.2)) { state.duplicateRow(row.id) }
                    }
                    rowActionButton("trash", disabled: state.rows.count <= 1) {
                        isDeletingRow = true
                    }
                }
                .opacity(isSelected ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Unified canvas + add button
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Unified canvas
                    ZStack(alignment: .topLeading) {
                        // Background tiles (one per template, no gap)
                        HStack(spacing: 0) {
                            ForEach(row.templates) { _ in
                                Rectangle()
                                    .fill(row.bgColor.gradient)
                                    .frame(width: row.displayWidth, height: row.displayHeight)
                            }
                        }

                        // Guideline separators
                        if row.showBorders {
                            ForEach(1..<row.templates.count, id: \.self) { i in
                                Rectangle()
                                    .fill(.white.opacity(0.2))
                                    .frame(width: 1, height: row.displayHeight)
                                    .offset(x: row.displayWidth * CGFloat(i))
                            }
                        }

                        // Shared shapes layer
                        ForEach(row.shapes) { shape in
                            CanvasShapeView(
                                shape: shape,
                                displayScale: row.displayScale,
                                isSelected: shape.id == state.selectedShapeId,
                                onSelect: { state.selectedShapeId = shape.id },
                                onUpdate: { state.updateShape($0) },
                                onDelete: { state.deleteShape(shape.id) }
                            )
                        }
                    }
                    .frame(
                        width: row.totalDisplayWidth,
                        height: row.displayHeight
                    )
                    .clipped()
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { state.deselectShape() }

                    // Add button
                    AddTemplateButton(width: row.displayWidth, height: row.displayHeight) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.addTemplate(to: row.id)
                        }
                    }
                    .padding(.leading, 12)

                    // Per-template control bars
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Per-template control bars
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                        TemplateControlBar(
                            index: index,
                            canDelete: row.templates.count > 1,
                            displayWidth: row.displayWidth,
                            templateWidth: row.templateWidth,
                            templateHeight: row.templateHeight,
                            bgColor: row.bgColor,
                            shapes: row.shapes,
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    state.removeTemplate(template.id, from: row.id)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            state.selectedRowId = row.id
        }
        .background(isSelected ? Color.accentColor.opacity(0.04) : Color.clear)
        .alert("Delete Row", isPresented: $isDeletingRow) {
            Button("Delete", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete \"\(row.label)\"?")
        }
    }

    fileprivate func rowActionButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
    }
}

// MARK: - Template Control Bar

private struct TemplateControlBar: View {
    let index: Int
    let canDelete: Bool
    let displayWidth: CGFloat
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    let bgColor: Color
    let shapes: [CanvasShapeModel]
    var onDelete: () -> Void
    @State private var isDeletingTemplate = false

    var body: some View {
        HStack(spacing: 6) {
            templateActionButton("eye", tooltip: "Preview") {
                previewScreenshot()
            }
            templateActionButton("arrow.down.circle", tooltip: "Download") {
                downloadScreenshot()
            }
            Spacer()
            if canDelete {
                templateActionButton("trash", tooltip: "Delete") {
                    isDeletingTemplate = true
                }
            }
        }
        .padding(.horizontal, 4)
        .frame(width: displayWidth)
        .alert("Delete Screenshot", isPresented: $isDeletingTemplate) {
            Button("Delete", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this screenshot?")
        }
    }

    private func templateActionButton(_ icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(tooltip)
    }

    private func renderPNGData() -> Data? {
        let tLeft = CGFloat(index) * templateWidth
        let tRight = tLeft + templateWidth
        let templateShapes = shapes.filter { s in
            let cx = s.x + s.width / 2
            return cx >= tLeft && cx < tRight
        }

        let shapeViews = ForEach(templateShapes) { shape in
            CanvasShapeView(
                shape: shape.duplicated(offsetX: -tLeft),
                displayScale: 1.0,
                isSelected: false,
                onSelect: {},
                onUpdate: { _ in },
                onDelete: {}
            )
        }

        let view = ZStack {
            Rectangle().fill(bgColor.gradient)
            shapeViews
        }
        .frame(width: templateWidth, height: templateHeight)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(width: templateWidth, height: templateHeight)

        guard let cgImage = renderer.cgImage else { return nil }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: templateWidth, height: templateHeight))
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
    }

    private func previewScreenshot() {
        guard let pngData = renderPNGData() else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("screenshot-\(index + 1).png")
        try? pngData.write(to: tempURL)
        QuickLookCoordinator.shared.preview(imageAt: tempURL)
    }

    private func downloadScreenshot() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "screenshot-\(index + 1).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let pngData = renderPNGData() else { return }
        try? pngData.write(to: url)
    }
}

// MARK: - Add Template Button

private struct AddTemplateButton: View {
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.primary.opacity(isHovered ? 0.04 : 0))
            )
            .contentShape(Rectangle())
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(isHovered ? .primary : .secondary)
            }
            .onHover { isHovered = $0 }
            .onTapGesture { action() }
            .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}
