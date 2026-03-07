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
                    rowActionButton("trash", tooltip: "Delete row", disabled: !canDelete) {
                        isDeletingRow = true
                    }
                }
                .opacity(isSelected || isRowHovered ? 1 : 0.65)
                .animation(.easeInOut(duration: 0.15), value: isSelected || isRowHovered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .onHover { isRowHovered = $0 }

            // Unified canvas + add button
            ScrollView(.horizontal, showsIndicators: false) {
                let dw = row.displayWidth(zoom: zoom)
                let dh = row.displayHeight(zoom: zoom)
                let ds = row.displayScale(zoom: zoom)

                VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    // Unified canvas
                    ZStack(alignment: .topLeading) {
                        // Background tiles (one per template, no gap)
                        HStack(spacing: 0) {
                            ForEach(row.templates) { _ in
                                row.backgroundFill
                                    .frame(width: dw, height: dh)
                            }
                        }

                        // Shared shapes layer
                        ForEach(row.activeShapes) { shape in
                            CanvasShapeView(
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
                                onDragEnd: { activeGuides = [] }
                            )
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
                            row: row,
                            index: index,
                            zoom: zoom,
                            screenshotImages: state.screenshotImages,
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
                .padding(.vertical, 12)
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

    private func tapSelectRow() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        state.selectRow(row.id)
    }

    private func rowActionButton(_ icon: String, tooltip: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .disabled(disabled)
        .help(tooltip)
    }
}
