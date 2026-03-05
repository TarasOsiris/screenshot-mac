import SwiftUI
import UniformTypeIdentifiers

struct EditorRowView: View {
    @Bindable var state: AppState
    let row: ScreenshotRow
    @State private var isDeletingRow = false

    private var isSelected: Bool {
        state.selectedRowId == row.id
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
                                    .frame(width: row.displayWidth(zoom: zoom), height: row.displayHeight(zoom: zoom))
                            }
                        }

                        // Shared shapes layer
                        ForEach(row.shapes.filter { row.showDevice || $0.type != .device }) { shape in
                            CanvasShapeView(
                                shape: shape,
                                displayScale: row.displayScale(zoom: zoom),
                                isSelected: shape.id == state.selectedShapeId,
                                onSelect: { state.selectedRowId = row.id; state.selectedShapeId = shape.id },
                                onUpdate: { state.updateShape($0) },
                                onDelete: { state.deleteShape(shape.id) }
                            )
                        }

                        // Guideline separators (always on top)
                        if row.showBorders {
                            ForEach(1..<row.templates.count, id: \.self) { i in
                                ZStack {
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: 0))
                                        path.addLine(to: CGPoint(x: 0, y: row.displayHeight(zoom: zoom)))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .foregroundStyle(.black)

                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: 0))
                                        path.addLine(to: CGPoint(x: 0, y: row.displayHeight(zoom: zoom)))
                                    }
                                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4], dashPhase: 4))
                                    .foregroundStyle(.white)
                                }
                                .frame(width: 1, height: row.displayHeight(zoom: zoom))
                                .offset(x: row.displayWidth(zoom: zoom) * CGFloat(i))
                                .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(
                        width: row.totalDisplayWidth(zoom: zoom),
                        height: row.displayHeight(zoom: zoom)
                    )
                    .clipped()
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture { state.deselectShape() }

                    // Add button
                    AddTemplateButton(width: row.displayWidth(zoom: zoom), height: row.displayHeight(zoom: zoom)) {
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
                        if index > 0 {
                            Divider()
                                .frame(height: 20)
                        }
                        TemplateControlBar(
                            row: row,
                            index: index,
                            zoom: zoom,
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
    let row: ScreenshotRow
    let index: Int
    let zoom: CGFloat
    var onDelete: () -> Void
    @State private var isDeletingTemplate = false

    private var canDelete: Bool { row.templates.count > 1 }

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
        .frame(width: row.displayWidth(zoom: zoom))
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

    private func previewScreenshot() {
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row) else { return }
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
        guard let pngData = ExportService.renderTemplatePNG(index: index, row: row) else { return }
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
