#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics
import ImageIO

/// CGImageSource-backed downsampling. Pure image work with no document dependency — it was on
/// `AppState` only because that is where the editor's image cache lives, and
/// `ProjectThumbnailService` already reached across for it.
nonisolated enum ImageDownsampler {
    /// Maximum pixel dimension for images stored in `screenshotImages` (editor display).
    /// Full-resolution images are loaded from disk on-demand for export.
    /// 1200px is enough for editor display at 2x zoom on retina, while
    /// reducing memory ~10x vs full App Store screenshot resolution.
    static let editorImageMaxDimension: CGFloat = 1200

/// Returns a downsampled thumbnail for editor display, falling back to the original image.
static func editorThumbnail(for image: NSImage) -> NSImage {
    guard let tiffData = image.tiffRepresentation else { return image }
    return downsampledImage(from: tiffData, maxDimension: editorImageMaxDimension) ?? image
}

/// Efficiently loads a downsampled image from a file URL using CGImageSource.
nonisolated static func downsampledImage(at url: URL, maxDimension: CGFloat) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
    return downsampledImage(from: source, maxDimension: maxDimension)
}

/// Downsamples from in-memory image data using CGImageSource (avoids disk round-trip).
nonisolated static func downsampledImage(from data: Data, maxDimension: CGFloat) -> NSImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
    return downsampledImage(from: source, maxDimension: maxDimension)
}

private nonisolated static func downsampledImage(from source: CGImageSource, maxDimension: CGFloat) -> NSImage? {
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ] as CFDictionary

    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}
}
