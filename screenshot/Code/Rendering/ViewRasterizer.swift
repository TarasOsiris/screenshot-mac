import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreImage

// Offscreen rasterization primitives: turn a SwiftUI view into pixels, blur, crop and
// composite them. No knowledge of rows, templates or locales — that lives in RowRenderer.
extension RowRenderer {
    nonisolated static func drawImage(
        _ image: NSImage,
        into background: NSImage,
        at origin: CGPoint,
        canvasSize: NSSize
    ) -> NSImage {
        composite(image, over: background, in: NSRect(origin: origin, size: image.size), canvasSize: canvasSize)
    }

    /// Draws `background` filling `canvasSize`, then `image` into `rect` on top.
    private nonisolated static func composite(
        _ image: NSImage,
        over background: NSImage,
        in rect: NSRect,
        canvasSize: NSSize
    ) -> NSImage {
        let canvasRect = NSRect(origin: .zero, size: canvasSize)
        #if os(macOS)
        guard let bitmapRep = bitmapRep(width: canvasSize.width, height: canvasSize.height) else {
            return background
        }
        let previousContext = NSGraphicsContext.current
        defer { NSGraphicsContext.current = previousContext }
        // Same reason as `renderViewToImage`: the graphics context and the CGImages `draw(in:)`
        // spawns are autoreleased, and a flatten runs once per template.
        autoreleasepool {
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)
            background.draw(in: canvasRect)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.current?.flushGraphics()
        }

        let output = NSImage(size: canvasSize)
        output.addRepresentation(bitmapRep)
        return output
        #else
        return offscreenImage(size: canvasSize) {
            background.draw(in: canvasRect)
            image.draw(in: rect)
        }
        #endif
    }

    private static let ciContext = CIContext()

    /// Applies CIGaussianBlur and crops the result back to the original image bounds.
    /// Uses CIAffineClamp to extend edge pixels so the blur kernel doesn't sample transparent pixels.
    private static func applyGaussianBlur(to image: NSImage, radius: Double) -> NSImage {
        guard radius > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        let ciImage = CIImage(cgImage: cgImage)
        let originalExtent = ciImage.extent

        guard let clamp = CIFilter(name: "CIAffineClamp"),
              let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        clamp.setValue(ciImage, forKey: kCIInputImageKey)
        clamp.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)

        blur.setValue(clamp.outputImage, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = blur.outputImage else { return image }

        let cropped = output.cropped(to: originalExtent)
        // CoreImage's intermediates are autoreleased and a full-row blur allocates megabytes.
        return autoreleasepool { () -> NSImage in
            guard let blurredCG = ciContext.createCGImage(cropped, from: originalExtent) else { return image }
            return NSImage(cgImage: blurredCG, size: image.size)
        }
    }

    /// Crops a rendered row background back to a single template slot.
    static func cropImage(_ image: NSImage, x: CGFloat, width: CGFloat, height: CGFloat) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        // bitmapImageRepForCachingDisplay creates bitmaps at screen backing scale (2x on Retina),
        // so cgImage pixel dimensions may be larger than the NSImage logical size.
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        let cropRect = CGRect(
            x: max(0, floor(x * scaleX)),
            y: 0,
            width: min(CGFloat(cgImage.width) - max(0, floor(x * scaleX)), ceil(width * scaleX)),
            height: min(CGFloat(cgImage.height), ceil(height * scaleY))
        ).integral

        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedCG = cgImage.cropping(to: cropRect) else {
            return image
        }

        return NSImage(cgImage: croppedCG, size: NSSize(width: width, height: height))
    }

    @MainActor
    static func renderBlurredViewToImage<V: View>(_ view: V, width: CGFloat, height: CGFloat, radius: Double, label: String) -> NSImage {
        let rendered = renderViewToImage(view, width: width, height: height, label: label)
        guard radius > 0 else { return rendered }
        let blurred = applyGaussianBlur(to: rendered, radius: radius)
        return flattenImage(blurred, over: rendered, width: width, height: height)
    }

    /// A render this slow is already an app-hang report waiting to happen — leave a crumb naming
    /// the view and its pixel size so the hang has something to point at.
    private static let slowRenderThreshold: TimeInterval = 0.5

    /// Render labels quote the row's label for local debugging (`showcase row 'Onboarding'`).
    /// That's user content, so quoted spans are elided before a label reaches a crash report.
    static func reportableRenderLabel(_ label: String) -> String {
        label.replacing(/'[^']*'/, with: "'…'")
    }

    @MainActor
    static func renderViewToImage<V: View>(_ view: V, width: CGFloat, height: CGFloat, label: String) -> NSImage {
        let startedAt = Date()
        defer {
            let elapsed = Date().timeIntervalSince(startedAt)
            if elapsed >= slowRenderThreshold {
                CrashReportingService.breadcrumb(.export, "Slow render", data: [
                    "label": reportableRenderLabel(label),
                    "pixels": Int(width * height),
                    "elapsed_ms": Int(elapsed * 1000),
                ], level: .warning)
            }
        }
        #if os(macOS)
        // Use NSHostingView + layer rendering into an explicit 1x CGContext.
        // bitmapImageRepForCachingDisplay implicitly scales by the screen's
        // backingScaleFactor, which breaks cropImage (it expects 1:1 pixel
        // dimensions matching model space). Rendering via CGContext with exact
        // pixel dimensions guarantees consistent output regardless of display.
        let pixelW = Int(ceil(width))
        let pixelH = Int(ceil(height))
        let rect = NSRect(x: 0, y: 0, width: pixelW, height: pixelH)
        guard let bitmapRep = bitmapRep(width: width, height: height) else {
            CrashReportingService.report(.renderProducedBlankImage, extra: [
                "label": reportableRenderLabel(label),
                "stage": "bitmapRep",
                "width": Int(width),
                "height": Int(height),
            ])
            return NSImage(size: NSSize(width: width, height: height))
        }

        // The hosting view and cacheDisplay's CoreGraphics temporaries are autoreleased, so
        // without a pool they accumulate across an export loop until the run loop drains.
        autoreleasepool {
            let hostingView = NSHostingView(
                rootView: view
                    .environment(\.isExportRendering, true)
                    .environment(\.layoutDirection, .leftToRight)
                    .frame(width: CGFloat(pixelW), height: CGFloat(pixelH), alignment: .topLeading)
                    .clipped()
            )
            hostingView.frame = rect
            hostingView.wantsLayer = true
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            hostingView.cacheDisplay(in: rect, to: bitmapRep)
        }

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmapRep)
        return image
        #else
        // iPad renders via SwiftUI ImageRenderer at 1x so pixel dimensions match model space
        // (cropImage depends on the mapping; it reads the real cgImage/size ratio so a sub-1
        // scale stays correct). A full-row background can exceed the GPU texture limit (~8192px)
        // — e.g. a wide multi-device row — and then ImageRenderer returns nil, leaving the
        // background transparent. Cap the scale so the longest side stays within the limit; a
        // slightly downscaled-but-present background beats a missing one (output is downscaled
        // anyway). Per-template shape renders are small, so they stay at 1x.
        let maxPixelDimension: CGFloat = 8192
        let safeScale = min(1, maxPixelDimension / max(width, height, 1))
        let renderer = ImageRenderer(content:
            view
                .environment(\.isExportRendering, true)
                .environment(\.layoutDirection, .leftToRight)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
        )
        renderer.scale = safeScale
        renderer.isOpaque = false
        if let image = renderer.uiImage {
            return image
        }
        CrashReportingService.report(.renderProducedBlankImage, extra: [
            "label": reportableRenderLabel(label),
            "stage": "imageRenderer",
            "width": Int(width),
            "height": Int(height),
            "scale": safeScale,
        ])
        return NSImage(size: NSSize(width: width, height: height))
        #endif
    }

    /// Draws `image` over `background` at full size — flattens shapes onto their background, and
    /// backs a blurred layer with its unblurred original so edge alpha fringes don't show through.
    nonisolated static func flattenImage(_ image: NSImage, over background: NSImage, width: CGFloat, height: CGFloat) -> NSImage {
        let size = NSSize(width: width, height: height)
        return composite(image, over: background, in: NSRect(origin: .zero, size: size), canvasSize: size)
    }

    #if os(macOS)
    nonisolated static func bitmapRep(width: CGFloat, height: CGFloat) -> NSBitmapImageRep? {
        let pixelW = max(Int(ceil(width)), 1)
        let pixelH = max(Int(ceil(height)), 1)
        let rep = NSBitmapImageRep(
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
        )
        rep?.size = NSSize(width: width, height: height)
        return rep
    }
    #else
    /// Offscreen 1x compositing helper for iPad (mirrors the macOS NSGraphicsContext path).
    nonisolated static func offscreenImage(size: CGSize, _ draw: () -> Void) -> UIImage {
        PlatformImageRenderer.image(size: size, draw)
    }
    #endif
}
