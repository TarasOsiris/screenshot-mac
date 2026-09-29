import SwiftUI

/// Crop mode, zoom and reset for an image shape on one line of the properties bar. The inspector
/// lays out the same leaves (`ImageCropModeButton`, `ImageCropResetButton`) in its own rows.
struct ImageCropControls: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID

    var body: some View {
        let isLocked = resolvedDocumentShape(shapeId)?.resolvedIsLocked ?? false
        HStack(spacing: 8) {
            ImageCropModeButton(state: state, shapeId: shapeId)
            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(.secondary)
            Slider(value: shapeBinding(shapeId, \.imageCropScale, continuous: true), in: ImageCrop.scaleRange)
                .frame(width: UIMetrics.SliderWidth.standard)
                .help("Zoom the picture inside its frame")
                .disabled(isLocked)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(.secondary)
            ImageCropResetButton(state: state, shapeId: shapeId)
        }
        .controlSize(.small)
    }
}

/// Enters and leaves crop mode; prominent while cropping, so the control says which mode the
/// canvas is in.
struct ImageCropModeButton: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID

    var body: some View {
        let isCropping = state.imageCrop.shapeId == shapeId
        // Locking ends crop mode, so the button never needs to stay reachable on a locked shape.
        let isLocked = resolvedDocumentShape(shapeId)?.resolvedIsLocked ?? false
        Button {
            state.toggleImageCrop(shapeId)
        } label: {
            if isCropping {
                Label("Done", systemImage: "checkmark")
            } else {
                Label("Crop", systemImage: "crop")
            }
        }
        .buttonStyle(ProminenceButtonStyle(isProminent: isCropping))
        .disabled(isLocked)
        .help(isLocked
            ? Text("Unlock the shape to crop it")
            : Text("Drag the picture to reposition it inside the frame (or double-click the image)"))
    }
}

struct ImageCropResetButton: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID

    var body: some View {
        let canReset = resolvedDocumentShape(shapeId).map(state.canResetImageCrop) ?? false
        ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset Crop", frameSize: UIMetrics.IconButton.frameSize, disabled: !canReset) {
            state.resetImageCrop(shapeId)
        }
    }
}
