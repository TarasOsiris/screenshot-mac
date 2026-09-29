import SwiftUI

/// Crop mode, zoom and reset for an image shape — shared by the properties bar and the inspector.
struct ImageCropControls: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var sliderWidth: CGFloat = UIMetrics.SliderWidth.standard

    var body: some View {
        let isCropping = state.imageCrop.shapeId == shapeId
        let hasCrop = resolvedDocumentShape(shapeId)?.imageCrop != nil
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { isCropping },
                set: { _ in state.toggleImageCrop(shapeId) }
            )) {
                Label("Crop", systemImage: "crop")
            }
            .toggleStyle(.button)
            .help("Drag the picture to reposition it inside the frame (or double-click the image)")

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: shapeBinding(shapeId, \.imageCropScale, continuous: true), in: ImageCrop.scaleRange)
                .frame(width: sliderWidth)
                .help("Zoom the picture inside its frame")
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)

            ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset Crop", frameSize: UIMetrics.IconButton.frameSize, disabled: !hasCrop) {
                state.resetImageCrop(shapeId)
            }
        }
        .controlSize(.small)
    }
}
