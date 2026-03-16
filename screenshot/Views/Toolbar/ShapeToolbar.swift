import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    private static let nonMenuTypes = ShapeType.allCases.filter { !ShapeType.shapeMenuTypes.contains($0) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
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
        .controlSize(.small)
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
        .controlSize(.small)
        .help("Add \(type.label)")
    }

    private func shapeCenter(for row: ScreenshotRow) -> CGPoint {
        CGPoint(
            x: state.visibleCanvasModelCenter?.x ?? row.templateWidth / 2,
            y: state.visibleCanvasModelCenter?.y ?? row.templateHeight / 2
        )
    }

    private func addShape(_ type: ShapeType) {
        guard let row = state.selectedRow else { return }
        let center = shapeCenter(for: row)
        let centerX = center.x
        let centerY = center.y

        let shape: CanvasShapeModel
        switch type {
        case .rectangle: shape = .defaultRectangle(centerX: centerX, centerY: centerY)
        case .circle: shape = .defaultCircle(centerX: centerX, centerY: centerY)
        case .star: shape = .defaultStar(centerX: centerX, centerY: centerY)
        case .text: shape = .defaultText(centerX: centerX, centerY: centerY)
        case .image: shape = .defaultImage(centerX: centerX, centerY: centerY)
        case .device:
            shape = .defaultDeviceFromRow(row, centerX: centerX, centerY: centerY)
        case .svg: return
        }

        state.addShape(shape)
    }

    private func addSvgShape(svgContent: String, size: CGSize, useColor: Bool, color: Color) {
        guard let row = state.selectedRow else { return }
        let center = shapeCenter(for: row)
        let scaledSize = SvgHelper.scaledSize(size)
        var shape = CanvasShapeModel.defaultSvg(centerX: center.x, centerY: center.y, svgContent: svgContent, size: scaledSize)
        if useColor {
            shape.svgUseColor = true
            shape.color = color
        }
        state.addShape(shape)
    }
}
