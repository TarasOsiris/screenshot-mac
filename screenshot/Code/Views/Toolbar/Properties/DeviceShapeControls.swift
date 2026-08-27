import SwiftUI

struct DeviceShapeControls<DevicePickerContent: View>: View {
    let shape: CanvasShapeModel
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void
    let onResetLocaleImage: () -> Void
    private let devicePickerContent: DevicePickerContent

    init(
        shape: CanvasShapeModel,
        showsLocaleImageReset: Bool,
        onPickImage: @escaping () -> Void,
        onImageSelected: @escaping (NSImage) -> Void,
        onResetLocaleImage: @escaping () -> Void,
        @ViewBuilder devicePickerContent: () -> DevicePickerContent
    ) {
        self.shape = shape
        self.showsLocaleImageReset = showsLocaleImageReset
        self.onPickImage = onPickImage
        self.onImageSelected = onImageSelected
        self.onResetLocaleImage = onResetLocaleImage
        self.devicePickerContent = devicePickerContent()
    }

    var body: some View {
        ShapePropertiesSection {
            devicePickerContent

            #if os(macOS)
            if shape.screenshotFileName != nil {
                ShapePropertiesSeparator()

                Button(action: onPickImage) {
                    Label("Replace Image", systemImage: "photo.badge.arrow.down")
                }
                .propertiesBarSecondaryButton()

                if showsLocaleImageReset {
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
                        onResetLocaleImage()
                    }
                }
            }
            #else
            ShapePropertiesSeparator()

            ImageSourceMenu(onImage: onImageSelected) {
                Label(shape.screenshotFileName == nil ? "Add Screenshot" : "Replace Image", systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()

            if showsLocaleImageReset {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
                    onResetLocaleImage()
                }
            }
            #endif
        }
    }
}
