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

    /// CFDictionary isn't Sendable, so build it per call rather than caching a global.
    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    /// Returns a downsampled thumbnail for editor display, falling back to the original image.
    static func editorThumbnail(for image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation else { return image }
        return downsampledImage(from: tiffData, maxDimension: editorImageMaxDimension) ?? image
    }

    /// Efficiently loads a downsampled image from a file URL using CGImageSource.
    static func downsampledImage(at url: URL, maxDimension: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return downsampledImage(from: source, maxDimension: maxDimension)
    }

    /// Downsamples from in-memory image data using CGImageSource (avoids disk round-trip).
    static func downsampledImage(from data: Data, maxDimension: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return downsampledImage(from: source, maxDimension: maxDimension)
    }

    /// Off-actor thumbnail read straight from the written file, so a bulk import never holds the
    /// full-resolution bytes in memory just to make a thumbnail. Returns a `CGImage` rather than an
    /// `NSImage` so nothing non-`Sendable` crosses; the caller wraps it back up on its own actor.
    /// `@concurrent` is load-bearing — `nonisolated` alone would inherit the caller's executor.
    @concurrent static func downsampledCGImageOffMain(at url: URL, maxDimension: CGFloat) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return downsampledCGImage(from: source, maxDimension: maxDimension)
    }

    private static func downsampledImage(from source: CGImageSource, maxDimension: CGFloat) -> NSImage? {
        guard let cgImage = downsampledCGImage(from: source, maxDimension: maxDimension) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private static func downsampledCGImage(from source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let span = PerfSignpost.begin("ImageDownsampler.downsample", "max=\(Int(maxDimension))")
        defer { PerfSignpost.end("ImageDownsampler.downsample", span) }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        // Editor-only: every caller of this feeds `AppState.screenshotImages`, a background editor
        // thumbnail or a project card. Export reloads full resolution through
        // `AppState.loadFullResolutionImages`, which is untouched. Doing the conversion here — where
        // we are already off the main actor — is what stops CoreAnimation doing it at commit time
        // for every P3 screenshot the user imported.
        return EditorImagePresentation.displayReady(thumbnail) ?? thumbnail
    }
}
