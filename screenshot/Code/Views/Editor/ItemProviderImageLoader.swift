import AppKit
import UniformTypeIdentifiers

enum ItemProviderImageLoader {
    /// Loads an image from an NSItemProvider, calling completion on the main queue with nil on failure.
    static func loadImage(from provider: NSItemProvider, completion: @escaping (NSImage?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                let image = url.flatMap { NSImage(contentsOf: $0) }
                DispatchQueue.main.async { completion(image) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                guard let url = url,
                      let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                      let uttype = UTType(typeId),
                      uttype.conforms(to: .image) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let image = NSImage.fromSecurityScopedURL(url)
                DispatchQueue.main.async { completion(image) }
            }
        } else {
            DispatchQueue.main.async { completion(nil) }
        }
    }
}
