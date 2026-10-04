#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension DeviceModelRenderer {
    nonisolated(unsafe) private static let screenTextureCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 16
        cache.totalCostLimit = decodedImageCacheByteLimit
        return cache
    }()

    static func preparedScreenContents(from contents: CGImage?, identity: String?) -> Any {
        guard let contents else { return NSColor.white }
        return normalizedScreenContents(contents, identity: identity) ?? contents
    }

    /// `normalizedScreenCGImage` redraws the whole screenshot, and a rotation drag asks for the same
    /// one every tick. Editor-only by construction — `DeviceModelSnapshotRequest.make` withholds the
    /// identity on export, whose raster differs from the editor's thumbnail in colour but not always
    /// in size. The size still rides in the key so a second caller can't reintroduce that collision.
    static func normalizedScreenContents(_ source: CGImage, identity: String?) -> CGImage? {
        guard let identity else { return normalizedScreenCGImage(from: source) }
        let cacheKey = "\(identity)|\(source.width)x\(source.height)" as NSString
        if let cached = screenTextureCache.object(forKey: cacheKey) { return cached }
        guard let normalized = normalizedScreenCGImage(from: source) else { return nil }
        screenTextureCache.setObject(normalized, forKey: cacheKey, cost: normalized.width * normalized.height * 4)
        return normalized
    }

    /// The caller's actor pulls the `CGImage` off the non-`Sendable` `NSImage`; this redraw — a
    /// full-size `CGContext.draw` — is the half that runs on the render executor.
    static func screenContents(from image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        #if os(macOS)
        if let direct = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return direct }
        #else
        if let direct = image.cgImage { return direct }
        #endif
        // An image with no bitmap representation (vector- or PDF-backed) used to be handed to
        // SceneKit whole and rasterized there. It can't cross to the render executor, so rasterize
        // it here instead — otherwise `preparedScreenContents` falls through to white and the
        // device renders a blank screen, silently, in export as well as the editor.
        return rasterizedScreenContents(from: image)
    }

    private static func rasterizedScreenContents(from image: NSImage) -> CGImage? {
        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        #if os(macOS)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        image.draw(in: rect)
        UIGraphicsPopContext()
        #endif
        return context.makeImage()
    }

    private static func normalizedScreenCGImage(from source: CGImage) -> CGImage? {
        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(source, in: rect)
        return context.makeImage()
    }
}
