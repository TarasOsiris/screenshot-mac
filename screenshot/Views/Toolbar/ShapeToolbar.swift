import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState
    @State private var isSvgDialogPresented = false

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
            ForEach(ShapeType.allCases, id: \.self) { type in
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
            SvgPasteDialog(isPresented: $isSvgDialogPresented) { svgContent, size in
                addSvgShape(svgContent: svgContent, size: size)
            }
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
        case .device:
            var device = CanvasShapeModel.defaultDevice(centerX: centerX, centerY: centerY, templateHeight: row.templateHeight, category: row.defaultDeviceCategory)
            if let frameId = row.defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
                device.deviceCategory = frame.fallbackCategory
                device.deviceFrameId = frame.id
                device.adjustToDeviceAspectRatio(centerX: centerX)
            }
            shape = device
        case .svg: return
        }

        state.addShape(shape)
    }

    private func addSvgShape(svgContent: String, size: CGSize) {
        guard let row = state.selectedRow else { return }
        let centerX = row.templateWidth / 2
        let centerY = row.templateHeight / 2
        let scaledSize = SvgHelper.scaledSize(size)
        let shape = CanvasShapeModel.defaultSvg(centerX: centerX, centerY: centerY, svgContent: svgContent, size: scaledSize)
        state.addShape(shape)
    }
}
