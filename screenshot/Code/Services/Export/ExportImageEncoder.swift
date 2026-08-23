#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics

enum ExportImageEncoder {
    /// Every nil below surfaces to the user as a bare `ExportError.renderFailed`; naming the
    /// stage is the only way to tell a zero-size image from an out-of-memory CGContext.
    private nonisolated static func reportEncodeFailure(_ stage: String, extra: [String: Any] = [:]) {
        CrashReportingService.report(.imageEncodeFailed, extra: extra.merging(["stage": stage]) { current, _ in current })
    }

    nonisolated static func encode(_ image: NSImage, format: ExportImageFormat) -> Data? {
        switch format {
        case .png:
            return opaquePNGData(from: image)
        case .jpeg:
            return opaqueJPEGData(from: image)
        }
    }

    /// Alpha-preserving PNG encode straight from the backing CGImage — no TIFF
    /// serialize/re-parse round trip.
    nonisolated static func pngData(from image: NSImage) -> Data? {
        #if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            reportEncodeFailure("cgImage")
            return nil
        }
        return pngData(fromCGImage: cgImage)
        #else
        return image.pngData()
        #endif
    }

    /// Encode PNG with no alpha channel by flattening onto an opaque white background.
    nonisolated static func opaquePNGData(from image: NSImage) -> Data? {
        guard let opaque = opaqueCGImage(from: image) else { return nil }
        return encode(cgImage: opaque, as: .png)
    }

    /// Opaque PNG encode for callers that render on the main actor: the bitmap is pulled here (on
    /// the caller's actor, since `NSImage` isn't Sendable) and the CPU work runs off-actor.
    // Must run on the caller's actor to read the non-Sendable NSImage; the @concurrent overload
    // below is what offloads.
    // swiftlint:disable:next inherited_executor_async
    nonisolated static func opaquePNGDataOffMain(from image: NSImage) async -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            reportEncodeFailure("cgImage")
            return nil
        }
        return await opaquePNGDataOffMain(fromCGImage: source)
    }

    /// `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    @concurrent nonisolated static func opaquePNGDataOffMain(fromCGImage source: CGImage) async -> Data? {
        guard let opaque = opaqueCGImage(fromSource: source) else { return nil }
        return encode(cgImage: opaque, as: .png)
    }

    /// Alpha-preserving PNG encode from a bitmap already in hand. Callers that are themselves
    /// off-actor use this directly; `pngDataOffMain` is the wrapper for main-actor callers.
    nonisolated static func pngData(fromCGImage source: CGImage) -> Data? {
        encode(cgImage: source, as: .png)
    }

    /// Alpha-preserving counterpart to `opaquePNGDataOffMain`, for paths that must not flatten
    /// transparency (screenshot import — Remove Background depends on alpha surviving a re-save).
    /// `@concurrent` is load-bearing — see the concurrency note in CLAUDE.md.
    @concurrent nonisolated static func pngDataOffMain(fromCGImage source: CGImage) async -> Data? {
        pngData(fromCGImage: source)
    }

    /// Encode JPEG from an opaque bitmap so transparent pixels are composited consistently.
    nonisolated static func opaqueJPEGData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        guard let opaque = opaqueCGImage(from: image) else { return nil }
        return encode(cgImage: opaque, as: .jpeg, compression: compression)
    }

    /// Composite onto a white background via CGContext, returning an opaque CGImage.
    private nonisolated static func opaqueCGImage(from image: NSImage) -> CGImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            reportEncodeFailure("cgImage")
            return nil
        }
        return opaqueCGImage(fromSource: source)
    }

    private nonisolated static func opaqueCGImage(fromSource source: CGImage) -> CGImage? {
        let w = source.width
        let h = source.height
        guard w > 0, h > 0 else {
            reportEncodeFailure("emptySource", extra: ["width": w, "height": h])
            return nil
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            reportEncodeFailure("cgContext", extra: ["width": w, "height": h])
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(rect)
        ctx.draw(source, in: rect)

        guard let opaque = ctx.makeImage() else {
            reportEncodeFailure("makeImage", extra: ["width": w, "height": h])
            return nil
        }
        return opaque
    }

    private nonisolated static func encode(cgImage: CGImage, as format: ExportImageFormat, compression: CGFloat = 0.9) -> Data? {
        #if os(macOS)
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let data: Data?
        switch format {
        case .png:
            data = bitmap.representation(using: .png, properties: [:])
        case .jpeg:
            data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: compression])
        }
        if data == nil {
            reportEncodeFailure("representation", extra: ["format": format.rawValue, "width": cgImage.width, "height": cgImage.height])
        }
        return data
        #else
        let image = UIImage(cgImage: cgImage)
        let data: Data?
        switch format {
        case .png:
            data = image.pngData()
        case .jpeg:
            data = image.jpegData(compressionQuality: compression)
        }
        if data == nil {
            reportEncodeFailure("representation", extra: ["format": format.rawValue, "width": cgImage.width, "height": cgImage.height])
        }
        return data
        #endif
    }
}
