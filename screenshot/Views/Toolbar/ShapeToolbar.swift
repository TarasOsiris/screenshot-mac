import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
            shapeButton("rectangle.fill", label: "Rectangle") {
                addShape(.rectangle)
            }
            shapeButton("circle.fill", label: "Circle") {
                addShape(.circle)
            }
            shapeButton("textformat", label: "Text") {
                addShape(.text)
            }
            shapeButton("photo", label: "Image") {
                addShape(.image)
            }
            shapeButton("iphone", label: "Device") {
                addShape(.device)
            }
            shapeButton("chevron.left.forwardslash.chevron.right", label: "SVG") {
                isSvgDialogPresented = true
            }
        }
        .sheet(isPresented: $isSvgDialogPresented) {
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size in
                addSvgShape(svgContent: svgContent, size: size)
            }
        }
    }

    private func shapeButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Add \(label)")
    }

    private func addShape(_ type: ShapeType) {
        guard let row = state.selectedRow else { return }
        let centerX = row.templateWidth / 2
        let centerY = row.templateHeight / 2

        let shape: CanvasShapeModel
        switch type {
        case .rectangle: shape = .defaultRectangle(centerX: centerX, centerY: centerY)
        case .circle: shape = .defaultCircle(centerX: centerX, centerY: centerY)
        case .text: shape = .defaultText(centerX: centerX, centerY: centerY)
        case .image: shape = .defaultImage(centerX: centerX, centerY: centerY)
        case .device: shape = .defaultDevice(centerX: centerX, centerY: centerY, templateHeight: row.templateHeight)
        case .svg: return
        }

        state.addShape(shape)
    }

    private func addSvgShape(svgContent: String, size: CGSize) {
        guard let row = state.selectedRow else { return }
        let centerX = row.templateWidth / 2
        let centerY = row.templateHeight / 2
        // Scale SVG to fit reasonably (max 400px in either dimension)
        let maxDim: CGFloat = 400
        let scale = min(maxDim / max(size.width, 1), maxDim / max(size.height, 1), 1)
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        let shape = CanvasShapeModel.defaultSvg(centerX: centerX, centerY: centerY, svgContent: svgContent, size: scaledSize)
        state.addShape(shape)
    }
}
