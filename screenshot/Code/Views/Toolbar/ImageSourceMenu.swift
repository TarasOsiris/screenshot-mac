#if os(iOS)
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// iPad image-source dropdown: lets the user pull an image from the photo library, the camera,
/// or the Files app. Each source resolves to an `NSImage` (UIImage on iOS) handed back via `onImage`.
/// The "Take Photo" item is hidden when no camera is available (e.g. on the simulator).
struct ImageSourceMenu<MenuLabel: View>: View {
    let onImage: (NSImage) -> Void
    @ViewBuilder var label: () -> MenuLabel

    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false

    var body: some View {
        Menu {
            Button {
                showPhotoPicker = true
            } label: {
                Label("Photo Library", systemImage: "photo.on.rectangle")
            }

            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera")
                }
            }

            Button {
                showFileImporter = true
            } label: {
                Label("Choose File", systemImage: "folder")
            }
        } label: {
            label()
        }
        .menuStyle(.borderlessButton)
        .modifier(ImageSourcePresenters(
            showPhotoPicker: $showPhotoPicker,
            showCamera: $showCamera,
            showFileImporter: $showFileImporter,
            onImage: onImage
        ))
    }
}

/// Boolean-triggered image-source chooser for call sites that have no menu anchor (canvas
/// double-tap, context-menu "Replace Image…"). Presents the same Photo Library / Camera / Files
/// options as `ImageSourceMenu`, but via a confirmation dialog. Apply through `.imageSourcePicker`.
struct ImageSourcePickerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onImage: (NSImage) -> Void

    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFileImporter = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add Image", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Photo Library") { showPhotoPicker = true }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") { showCamera = true }
                }
                Button("Choose File") { showFileImporter = true }
            }
            .modifier(ImageSourcePresenters(
                showPhotoPicker: $showPhotoPicker,
                showCamera: $showCamera,
                showFileImporter: $showFileImporter,
                onImage: onImage
            ))
    }
}

/// Shared plumbing for the three image sources, driven by external bindings. Used by both
/// `ImageSourceMenu` (inline menu items) and `ImageSourcePickerModifier` (confirmation dialog)
/// so the photo-library / camera / file-importer wiring lives in one place.
private struct ImageSourcePresenters: ViewModifier {
    @Binding var showPhotoPicker: Bool
    @Binding var showCamera: Bool
    @Binding var showFileImporter: Bool
    let onImage: (NSImage) -> Void

    @State private var photoItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    let loaded = try? await item.loadTransferable(type: Data.self)
                    let image = loaded.flatMap { $0 }.flatMap { NSImage(data: $0) }
                    await MainActor.run {
                        if let image { deliver(image) }
                        photoItem = nil
                    }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker(onImage: deliver)
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.image]) { result in
                if case .success(let url) = result, let image = NSImage.fromSecurityScopedURL(url) {
                    deliver(image)
                }
            }
    }

    /// Bake in the source's orientation before handing the image off. The save path encodes PNG
    /// (no orientation tag) via `UIImage.pngData()`, which ignores `imageOrientation` — so a
    /// portrait camera capture or EXIF-rotated photo would otherwise be stored sideways.
    private func deliver(_ image: NSImage) {
        onImage(image.uprightNormalized())
    }
}

private extension UIImage {
    /// Returns a copy whose pixels are rotated to match `.up` orientation, so encoders that drop
    /// the orientation flag (PNG) still produce an upright image.
    func uprightNormalized() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Wraps `UIImagePickerController` in `.camera` mode for capturing a photo.
private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (NSImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
#endif
