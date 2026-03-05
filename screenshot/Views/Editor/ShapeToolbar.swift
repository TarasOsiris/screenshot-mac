import SwiftUI

struct ShapeToolbar: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 8) {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func shapeButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.system(size: 9))
            }
            .frame(width: 48, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
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
        }

        state.addShape(shape)
    }
}
