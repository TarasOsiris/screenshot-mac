#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics

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
        #if os(macOS)
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
        #else
        return image.pngData()
        #endif
    }

    /// Encode PNG with no alpha channel by flattening onto an opaque white background.
    nonisolated static func opaquePNGData(from image: NSImage) -> Data? {
        guard let opaque = opaqueCGImage(from: image) else { return nil }
        return encode(cgImage: opaque, as: .png)
    }

    /// Encode JPEG from an opaque bitmap so transparent pixels are composited consistently.
    nonisolated static func opaqueJPEGData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        guard let opaque = opaqueCGImage(from: image) else { return nil }
        return encode(cgImage: opaque, as: .jpeg, compression: compression)
    }

    /// Composite onto a white background via CGContext, returning an opaque CGImage.
    private nonisolated static func opaqueCGImage(from image: NSImage) -> CGImage? {
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
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        ctx.draw(source, in: rect)

        return ctx.makeImage()
    }

    private nonisolated static func encode(cgImage: CGImage, as format: ExportImageFormat, compression: CGFloat = 0.9) -> Data? {
        #if os(macOS)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .png:
            return bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
        }
        #else
        let image = UIImage(cgImage: cgImage)
        switch format {
        case .png:
            return image.pngData()
        case .jpeg:
            return image.jpegData(compressionQuality: compression)
        }
        #endif
    }
}
