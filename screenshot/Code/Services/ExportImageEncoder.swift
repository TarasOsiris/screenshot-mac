import AppKit

enum ExportImageEncoder {
    nonisolated static func encode(_ image: NSImage, format: ExportImageFormat) -> Data? {
        switch format {
        case .png:
            return opaquePNGData(from: image)
        case .jpeg:
            return opaqueJPEGData(from: image)
        }
    }

    nonisolated static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
    }

    /// Encode PNG with no alpha channel by flattening onto an opaque white background.
    nonisolated static func opaquePNGData(from image: NSImage) -> Data? {
        guard let bitmap = opaqueBitmap(from: image) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Encode JPEG from an opaque bitmap so transparent pixels are composited consistently.
    nonisolated static func opaqueJPEGData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        guard let bitmap = opaqueBitmap(from: image) else { return nil }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: compression]
        return bitmap.representation(using: .jpeg, properties: properties)
    }

    /// Composite onto white background via CGContext, returning an opaque NSBitmapImageRep directly.
    private nonisolated static func opaqueBitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = source.width
        let h = source.height
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(CGColor.white)
        ctx.fill(rect)
        ctx.draw(source, in: rect)

        guard let opaqueRef = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: opaqueRef)
    }
}
