import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Boolean-triggered image picker for call sites without a menu anchor. On iPad it offers the
    /// full source chooser (Photo Library / Camera / Files) so every entry point matches
    /// `ImageSourceMenu`; on macOS it falls back to the standard file importer.
    @ViewBuilder
    func imageSourcePicker(isPresented: Binding<Bool>, onImage: @escaping (NSImage) -> Void) -> some View {
        #if os(iOS)
        modifier(ImageSourcePickerModifier(isPresented: isPresented, onImage: onImage))
        #else
        fileImporter(isPresented: isPresented, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task { @MainActor in
                guard let image = await NSImage.fromSecurityScopedURLOffMain(url) else { return }
                onImage(image)
            }
        }
        #endif
    }
}
