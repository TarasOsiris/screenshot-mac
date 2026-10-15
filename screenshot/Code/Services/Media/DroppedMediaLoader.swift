#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers

/// What a dropped file turned out to be.
enum DroppedMedia {
    case svg(String)
    case image(NSImage)
}

/// Decodes dropped files. Call inside the item provider's callback: the temporary URL it hands
/// over is deleted as soon as that returns.
nonisolated enum DroppedMediaLoader {
    enum SvgFailure: Error {
        case unreadable
        case unrenderable
    }

    /// `confirmingImageType` for a generic file URL, which promises nothing about its contents.
    static func image(at url: URL, confirmingImageType: Bool) -> NSImage? {
        if confirmingImageType {
            guard let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                  let type = UTType(typeId),
                  type.conforms(to: .image) else { return nil }
        }
        return NSImage.fromSecurityScopedURL(url)
    }

    /// An `.svg` file as sanitized markup, otherwise an image.
    static func media(at url: URL, confirmingImageType: Bool) -> DroppedMedia? {
        if let sanitized = SvgHelper.loadAndSanitize(from: url) { return .svg(sanitized) }
        return image(at: url, confirmingImageType: confirmingImageType).map(DroppedMedia.image)
    }

    /// Sanitized SVG markup that draws, with the size it draws at.
    static func renderableSvg(at url: URL) throws(SvgFailure) -> (content: String, naturalSize: CGSize) {
        guard let data = try? Data(contentsOf: url), let sanitized = SvgHelper.sanitize(svgData: data) else { throw .unreadable }
        guard let size = SvgHelper.renderableSize(of: sanitized) else { throw .unrenderable }
        return (sanitized, size)
    }

    /// Loads an image from a provider, calling `completion` on the main actor with nil on failure.
    static func loadImage(from provider: NSItemProvider, completion: @escaping @MainActor (NSImage?) -> Void) {
        let type: UTType
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            type = .image
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            type = .fileURL
        } else {
            Task { @MainActor in completion(nil) }
            return
        }
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
            let image = url.flatMap { image(at: $0, confirmingImageType: type == .fileURL) }
            Task { @MainActor in completion(image) }
        }
    }
}
