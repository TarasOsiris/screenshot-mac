import SwiftUI

struct DeviceShapeControls<DevicePickerContent: View>: View {
    let shape: CanvasShapeModel
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void
    private let devicePickerContent: DevicePickerContent

    init(
        shape: CanvasShapeModel,
        onPickImage: @escaping () -> Void,
        onImageSelected: @escaping (NSImage) -> Void,
        @ViewBuilder devicePickerContent: () -> DevicePickerContent
    ) {
        self.shape = shape
        self.onPickImage = onPickImage
        self.onImageSelected = onImageSelected
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
                .localeOverridden(.image)
            }
            #else
            ShapePropertiesSeparator()

            ImageSourceMenu(onImage: onImageSelected) {
                Label(shape.screenshotFileName == nil ? "Add Screenshot" : "Replace Image", systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            .localeOverridden(.image)
            #endif
        }
    }
}
