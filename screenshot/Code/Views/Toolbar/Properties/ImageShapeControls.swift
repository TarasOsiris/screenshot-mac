import SwiftUI

struct ImageShapeControls: View {
    let buttonTitle: LocalizedStringKey
    let onPickImage: () -> Void
    let onImageSelected: (NSImage) -> Void

    var body: some View {
        ShapePropertiesSection {
            #if os(macOS)
            Button(action: onPickImage) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            .localeOverridden(.image)
            #else
            ImageSourceMenu(onImage: onImageSelected) {
                Label(buttonTitle, systemImage: "photo.badge.arrow.down")
            }
            .propertiesBarSecondaryButton()
            .localeOverridden(.image)
            #endif
        }
    }
}
