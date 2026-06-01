import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    private static let nonMenuTypes = ShapeType.allCases.filter { !ShapeType.shapeMenuTypes.contains($0) }

    /// Touch targets need more room on iPad; macOS keeps the compact inspector density.
    private var buttonControlSize: ControlSize {
        #if os(macOS)
        .small
        #else
        .large
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(macOS)
        6
        #else
        10
        #endif
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 2), spacing: gridSpacing) {
            shapesMenu
            ForEach(Self.nonMenuTypes, id: \.self) { type in
                shapeButton(type) {
                    if type == .svg {
                        isSvgDialogPresented = true
                    } else {
                        addShape(type)
                    }
                }
            }
        }
        .coachPopover(step: .shapes, state: state, arrowEdge: .trailing)
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size, useColor, color in
                addSvgShape(svgContent: svgContent, size: size, useColor: useColor, color: color)
            }
        }
    }

    @State private var isShapesMenuPresented = false

    private var shapesMenu: some View {
        Button {
            isShapesMenuPresented = true
        } label: {
            Label("Shapes", systemImage: "square.on.circle")
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(buttonControlSize)
        .help("Add shape")
        .popover(isPresented: $isShapesMenuPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(ShapeType.shapeMenuTypes, id: \.self) { type in
                    Button(action: {
                        isShapesMenuPresented = false
                        addShape(type)
                    }) {
                        Label(type.label, systemImage: type.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .frame(minWidth: 140)
        }
    }

    private func shapeButton(_ type: ShapeType, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(type.label, systemImage: type.icon)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(buttonControlSize)
        .help("Add \(type.label)")
    }

    private func addShape(_ type: ShapeType) {
        guard let row = state.selectedRow else { return }
        let center = state.shapeCenter(for: row)
        guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: center.x, centerY: center.y) else { return }
        state.addShape(shape)
    }

    private func addSvgShape(svgContent: String, size: CGSize, useColor: Bool, color: Color) {
        guard let row = state.selectedRow else { return }
        let center = state.shapeCenter(for: row)
        let scaledSize = SvgHelper.scaledSize(size, maxDim: row.svgMaxDimension)
        var shape = CanvasShapeModel.defaultSvg(centerX: center.x, centerY: center.y, svgContent: svgContent, size: scaledSize)
        if useColor {
            shape.svgUseColor = true
            shape.color = color
        }
        state.addShape(shape)
    }
}
