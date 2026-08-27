import SwiftUI

struct ImageShapeControls: View {
    let buttonTitle: LocalizedStringKey
    let showsLocaleImageReset: Bool
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void
    let onResetLocaleImage: () -> Void

    var body: some View {
        ShapePropertiesSection {
            #if os(macOS)
            Button(action: onPickImage) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            #else
            ImageSourceMenu(onImage: onImageSelected) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            #endif

            if showsLocaleImageReset {
                ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset to base-language image", frameSize: UIMetrics.IconButton.frameSize) {
                    onResetLocaleImage()
                }
            }
        }
    }
}
