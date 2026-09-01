import CoreGraphics

/// Puts a raster into the form the editor's window backing store can upload without touching it.
///
/// `AppWindowManager` pins the main window to sRGB — the space exports are written in — so a raster
/// tagged with anything else (a Display P3 screenshot, say) makes CoreAnimation run a full ICC
/// conversion per image, lazily, on the main thread, inside its commit. A scrollbar-drag trace
/// showed ~97 ms of `CGColorTransformConvertUsingCMSConverter` there on the first pass over a
/// project, plus a `Deepmap2` decode for images that had never been drawn.
///
/// Editor-facing rasters only. Nothing on the export path may call this: `ViewRasterizer.bitmapRep`
/// and `ExportImageEncoder` define the exported bytes and stay DeviceRGB.
nonisolated enum EditorImagePresentation {
    /// Must match the window colour space set in `AppWindowManager.registerMainWindow`.
    static let colorSpace: CGColorSpace? = CGColorSpace(name: CGColorSpace.sRGB)

    /// Redraws `source` into sRGB and CoreAnimation's native layer-contents layout.
    ///
    /// A redraw, not `CGImage.copy(colorSpace:)` or `NSBitmapImageRep.retagging(with:)` — those
    /// reinterpret the existing numbers in a new space and shift the colour. The pixel layout
    /// matters as much as the space: handed anything but premultiplied BGRA8, CoreAnimation copies
    /// the image at commit even when the colour space already agrees. The draw also forces the
    /// decode, so a lazily-backed image stops paying for that on first paint.
    ///
    /// Returns `nil` if the context can't be made, so callers keep their original.
    static func displayReady(_ source: CGImage) -> CGImage? {
        guard let colorSpace, source.width > 0, source.height > 0 else { return nil }
        guard let context = CGContext(
            data: nil,
            width: source.width,
            height: source.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        return context.makeImage()
    }

    /// `@concurrent` is load-bearing: this target builds with `NonisolatedNonsendingByDefault`, so a
    /// plain `nonisolated async func` would inherit the caller's executor and offload nothing.
    @concurrent static func displayReadyOffMain(_ source: CGImage) async -> CGImage? {
        displayReady(source)
    }
}
