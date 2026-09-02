#if os(macOS)
import AppKit
#else
import SwiftDraw
import UIKit
#endif
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum PickedBackground {
    case image(NSImage)
    case svg(String)
}

nonisolated enum SvgHelper {
    nonisolated(unsafe) private static let rasterCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        cache.totalCostLimit = 192 * 1024 * 1024
        return cache
    }()

    /// Prompts the user for an image or SVG file and returns the picked content.
    /// Returns nil if the user cancels or the file cannot be loaded.
    @MainActor
    static func pickImageOrSvg() async -> PickedBackground? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .svg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        let response = CrashReportingService.withAppHangTrackingPaused { panel.runModal() }
        guard response == .OK, let url = panel.url else { return nil }
        guard let data = await Data.fromSecurityScopedURLOffMain(url) else { return nil }

        if url.pathExtension.lowercased() == "svg", let sanitized = sanitize(svgData: data) {
            return .svg(sanitized)
        }
        guard let image = NSImage(data: data) else { return nil }
        return .image(image)
        #else
        // iPad: image/SVG import via PhotosPicker/fileImporter is deferred to a follow-up.
        return nil
        #endif
    }

    /// Reads an SVG file from a URL, converts to String, and sanitizes it.
    /// Returns nil for non-SVG files.
    static func loadAndSanitize(from url: URL) -> String? {
        guard url.pathExtension.lowercased() == "svg",
              let data = try? Data(contentsOf: url) else { return nil }
        return sanitize(svgData: data)
    }

    static func sanitize(svgData: Data) -> String? {
        String(data: svgData, encoding: .utf8).map(sanitize)
    }

    static func sanitize(_ svg: String) -> String {
        var result = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*\"[^\"]*\"",
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s+on\\w+\\s*=\\s*'[^']*'",
            with: "",
            options: .regularExpression
        )
        return result
    }

    /// Parses the SVG's viewBox to get its natural size. Returns nil if no viewBox is found.
    static func parseViewBoxSize(_ svg: String) -> CGSize? {
        guard let viewBoxMatch = svg.range(of: "viewBox\\s*=\\s*[\"']([^\"']+)[\"']", options: .regularExpression) else { return nil }
        let attrValue = svg[viewBoxMatch]
        guard let quoteStart = attrValue.firstIndex(where: { $0 == "\"" || $0 == "'" }),
              quoteStart < attrValue.endIndex,
              let quoteEnd = attrValue[attrValue.index(after: quoteStart)...].firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let parts = svg[attrValue.index(after: quoteStart)..<quoteEnd]
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGSize(width: max(parts[2], 20), height: max(parts[3], 20))
    }

    static func parseSize(_ svg: String, fallbackImage: NSImage) -> CGSize {
        if let size = parseViewBoxSize(svg) { return size }
        let rep = fallbackImage.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(fallbackImage.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(fallbackImage.size.height))
        return CGSize(width: max(w, 20), height: max(h, 20))
    }

    static func scaledSize(_ size: CGSize, maxDim: CGFloat = 400, minDim: CGFloat = 256) -> CGSize {
        let largest = max(size.width, size.height, 1)
        let target = min(max(largest, minDim), maxDim)
        let scale = target / largest
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// Rewrites `fill`/`stroke` attributes in the SVG so the resulting image renders in `color`.
    /// Handles both single- and double-quoted attributes (templates and pasted SVGs use either).
    /// Preserves `fill="none"` / `stroke="none"` so non-filled paths stay unfilled.
    static func applyColor(_ color: Color, to svgContent: String) -> String {
        let hex = color.hexString
        var svg = svgContent
        for attr in ["fill", "stroke"] {
            svg = svg.replacingOccurrences(
                of: "\(attr)\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "\(attr)=\"\(hex)\"",
                options: .regularExpression
            )
            svg = svg.replacingOccurrences(
                of: "\(attr)\\s*=\\s*'(?!none')[^']*'",
                with: "\(attr)=\"\(hex)\"",
                options: .regularExpression
            )
        }
        // Set fill on the <svg> tag so elements without an explicit fill inherit the color
        if svg.range(of: "<svg\\b[^>]*\\bfill\\s*=", options: .regularExpression) == nil {
            svg = svg.replacingOccurrences(
                of: "<svg\\b",
                with: "<svg fill=\"\(hex)\"",
                options: .regularExpression
            )
        }
        return svg
    }

    /// Renders into the raster cache off the main actor; read the result back with
    /// `cachedRender`. `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    /// `color` must be a static color: dynamic/catalog colors resolve `hexString` against the
    /// current thread's appearance, which would key the insert differently than the read-back.
    @concurrent static func renderImageOffMain(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize?) async {
        _ = renderImage(from: svgContent, useColor: useColor, color: color, targetSize: targetSize)
    }

    static func renderImage(from svgContent: String, useColor: Bool, color: Color, targetSize requestedSize: CGSize? = nil) -> NSImage? {
        let targetSize = clampedRasterSize(requestedSize)
        let key = rasterCacheKey(svgContent: svgContent, useColor: useColor, color: color, targetSize: targetSize)
        if let cached = rasterCache.object(forKey: key) {
            return cached
        }
        let signpost = PerfSignpost.begin(
            "SvgHelper.render",
            pixels: Int((targetSize?.width ?? 0) * (targetSize?.height ?? 0))
        )
        defer { PerfSignpost.end("SvgHelper.render", signpost) }
        let svg = useColor ? applyColor(color, to: svgContent) : svgContent
        guard let data = svg.data(using: .utf8) else { return nil }
        #if os(macOS)
        guard let baseImage = NSImage(data: data) else { return nil }

        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
            rasterCache.setObject(baseImage, forKey: key, cost: rasterCost(for: baseImage.size))
            return baseImage
        }
        let pixelW = Int(targetSize.width)
        let pixelH = Int(targetSize.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW,
            pixelsHigh: pixelH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return baseImage }
        rep.size = targetSize
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        baseImage.draw(in: NSRect(origin: .zero, size: targetSize),
                       from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        let result = NSImage(size: targetSize)
        result.addRepresentation(rep)
        rasterCache.setObject(result, forKey: key, cost: rasterCost(for: targetSize))
        return result
        #else
        // UIKit has no native SVG support, so render the vector via SwiftDraw. Rasterize at scale 1
        // so the pixel dimensions equal targetSize, matching the macOS path above.
        guard let parsed = SwiftDraw.SVG(data: data) else { return nil }
        if let targetSize, targetSize.width > 0, targetSize.height > 0 {
            let image = parsed.rasterize(size: targetSize, scale: 1)
            rasterCache.setObject(image, forKey: key, cost: rasterCost(for: targetSize))
            return image
        }
        let image = parsed.rasterize(scale: 1)
        rasterCache.setObject(image, forKey: key, cost: rasterCost(for: image.size))
        return image
        #endif
    }

    static func cachedRender(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize? = nil) -> NSImage? {
        rasterCache.object(forKey: rasterCacheKey(
            svgContent: svgContent, useColor: useColor, color: color,
            targetSize: clampedRasterSize(targetSize)
        ))
    }

    /// Caps rasters at ~64 MB of bitmap. An oversized target (huge spanning shape × zoom) used to
    /// stall for seconds just zero-filling the bitmap (Sentry SCREENSHOT-BRO-R); past the cap the
    /// vector simply draws upscaled.
    private static let maxRasterPixels: CGFloat = 4096 * 4096

    static func clampedRasterSize(_ size: CGSize?) -> CGSize? {
        guard let size, size.width > 0, size.height > 0 else { return size }
        let pixels = size.width * size.height
        guard pixels > maxRasterPixels else { return size }
        let scale = (maxRasterPixels / pixels).squareRoot()
        return CGSize(width: max(1, (size.width * scale).rounded(.down)),
                      height: max(1, (size.height * scale).rounded(.down)))
    }

    private static func rasterCacheKey(svgContent: String, useColor: Bool, color: Color, targetSize: CGSize?) -> NSString {
        let width = targetSize.map { Int($0.width.rounded(.up)) } ?? 0
        let height = targetSize.map { Int($0.height.rounded(.up)) } ?? 0
        let colorKey = useColor ? color.hexString : "original"
        return "\(svgContent.hashValue)|\(useColor)|\(colorKey)|\(width)x\(height)" as NSString
    }

    private static func rasterCost(for size: CGSize) -> Int {
        max(1, Int(size.width.rounded(.up))) * max(1, Int(size.height.rounded(.up))) * 4
    }
}
