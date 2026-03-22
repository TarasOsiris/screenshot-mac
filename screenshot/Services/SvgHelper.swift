import AppKit
import SwiftUI

enum SvgHelper {
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

    static func parseSize(_ svg: String, fallbackImage: NSImage) -> CGSize {
        // Match viewBox with either single or double quotes
        if let viewBoxMatch = svg.range(of: "viewBox\\s*=\\s*[\"']([^\"']+)[\"']", options: .regularExpression) {
            let attrValue = svg[viewBoxMatch]
            if let quoteStart = attrValue.firstIndex(where: { $0 == "\"" || $0 == "'" }),
               quoteStart < attrValue.endIndex,
               let quoteEnd = attrValue[attrValue.index(after: quoteStart)...].firstIndex(where: { $0 == "\"" || $0 == "'" }) {
                let parts = svg[attrValue.index(after: quoteStart)..<quoteEnd]
                    .split(whereSeparator: { $0 == " " || $0 == "," })
                    .compactMap { Double($0) }
                if parts.count == 4 {
                    return CGSize(width: max(parts[2], 20), height: max(parts[3], 20))
                }
            }
        }
        let rep = fallbackImage.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(fallbackImage.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(fallbackImage.size.height))
        return CGSize(width: max(w, 20), height: max(h, 20))
    }

    static func scaledSize(_ size: CGSize, maxDim: CGFloat = 400) -> CGSize {
        let scale = min(maxDim / max(size.width, 1), maxDim / max(size.height, 1), 1)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    static func renderImage(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize? = nil) -> NSImage? {
        var svg = svgContent
        if useColor {
            let hex = color.hexString
            svg = svg.replacingOccurrences(
                of: "fill\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "fill=\"\(hex)\"",
                options: .regularExpression
            )
            svg = svg.replacingOccurrences(
                of: "stroke\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "stroke=\"\(hex)\"",
                options: .regularExpression
            )
        }
        guard let data = svg.data(using: .utf8) else { return nil }
        guard let baseImage = NSImage(data: data) else { return nil }

        guard let targetSize, targetSize.width > 0, targetSize.height > 0 else {
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
        return result
    }
}
