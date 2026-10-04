#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

nonisolated extension DeviceModelRenderer {
    nonisolated(unsafe) private static let snapshotImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = decodedImageCacheByteLimit
        return cache
    }()

    struct SnapshotKey: Hashable {
        let frameId: String
        /// Only `.export` renders may share an entry with an export. The other two draw the
        /// editor's screenshots — downsamples `EditorImagePresentation` already moved to sRGB —
        /// and below ~1200 px one of those shares both its file name and its pixel size with the
        /// untouched PNG export loads. A canvas raster collides when the 128 px rung lands on
        /// `ceil(points × 3)`; a project card collides outright, since it rasterizes at the same
        /// export pixel budget. Either would let a colour-converted texture define exported bytes.
        let renderContext: RasterRenderContext
        let pixelWidth: Int
        let pixelHeight: Int
        let hasScreenshot: Bool
        let screenshotIdentity: String?
        let screenshotWidth: Int
        let screenshotHeight: Int
        let pitch: Int
        let yaw: Int
        let materialFinish: String
        let ambient: Int
        let key: Int
        let rim: Int
        let bodyColor: String

        /// A screenshot with no stable identity can't be told apart from any other, so it
        /// must re-render rather than risk serving a different shape's snapshot.
        var isCacheable: Bool { !hasScreenshot || screenshotIdentity != nil }

        /// `frameId` carries the model, colourway and orientation, so a raster of the same one is the
        /// same silhouette — every other field settles within a render or two, and the fallback the
        /// view would show instead has no pose at all.
        func canStandInFor(_ other: Self) -> Bool {
            frameId == other.frameId
        }

        /// Only the raster resolution differs, which is the signature of a zoom step — the one change
        /// worth making a render wait, because it re-keys every device in the row at once.
        func matchesIgnoringPixelSize(_ other: Self) -> Bool {
            frameId == other.frameId
                && renderContext == other.renderContext
                && hasScreenshot == other.hasScreenshot
                && screenshotIdentity == other.screenshotIdentity
                && screenshotWidth == other.screenshotWidth
                && screenshotHeight == other.screenshotHeight
                && pitch == other.pitch
                && yaw == other.yaw
                && materialFinish == other.materialFinish
                && ambient == other.ambient
                && key == other.key
                && rim == other.rim
                && bodyColor == other.bodyColor
        }

        var cacheKey: NSString {
            [
                frameId,
                renderContext.rawValue,
                "\(pixelWidth)x\(pixelHeight)",
                screenshotIdentity ?? "no-image",
                "\(screenshotWidth)x\(screenshotHeight)",
                "p\(pitch)",
                "y\(yaw)",
                materialFinish,
                "a\(ambient)",
                "k\(key)",
                "r\(rim)",
                bodyColor
            ].joined(separator: "|") as NSString
        }
    }
    static func cachedSnapshot(for key: SnapshotKey) -> NSImage? {
        guard key.isCacheable else { return nil }
        return snapshotImageCache.object(forKey: key.cacheKey)
    }

    static func storeSnapshot(_ image: NSImage, for key: SnapshotKey) {
        guard key.isCacheable else { return }
        snapshotImageCache.setObject(image, forKey: key.cacheKey, cost: key.pixelWidth * key.pixelHeight * 4)
    }

    static func snapshotKey(
        frame: DeviceFrame,
        renderContext: RasterRenderContext,
        pixelSize: CGSize,
        screenshotImage: NSImage?,
        screenshotImageIdentity: String?,
        pitch: Double,
        yaw: Double,
        bodyMaterial: DeviceBodyMaterial,
        lighting: DeviceLighting,
        bodyColor: Color
    ) -> SnapshotKey {
        let imageSize = screenshotImage?.size ?? .zero
        let color = bodyColor.sRGBComponents
        let angleStep = renderContext == .canvas ? snapshotAngleStep : snapshotFineStep
        return SnapshotKey(
            frameId: frame.id,
            renderContext: renderContext,
            pixelWidth: max(1, Int(pixelSize.width.rounded(.up))),
            pixelHeight: max(1, Int(pixelSize.height.rounded(.up))),
            hasScreenshot: screenshotImage != nil,
            screenshotIdentity: screenshotImage == nil ? nil : screenshotImageIdentity,
            screenshotWidth: max(0, Int(imageSize.width.rounded())),
            screenshotHeight: max(0, Int(imageSize.height.rounded())),
            pitch: quantized(pitch, step: angleStep),
            yaw: quantized(yaw, step: angleStep),
            materialFinish: bodyMaterial.resolvedFinish.rawValue,
            ambient: quantized(lighting.resolvedAmbientIntensity),
            key: quantized(lighting.resolvedKeyIntensity),
            rim: quantized(lighting.resolvedRimIntensity),
            bodyColor: "\(quantized(Double(color.r)))-\(quantized(Double(color.g)))-\(quantized(Double(color.b)))-\(quantized(Double(color.a)))"
        )
    }

    /// The rung every key field uses by default, and the one export's pose angles keep.
    static let snapshotFineStep: Double = 0.001

    private static func quantized(_ value: Double, step: Double = snapshotFineStep) -> Int {
        Int((value / step).rounded())
    }

    /// Pose angles get a much coarser rung than the other key fields — **on the canvas only**. A
    /// rotation slider sweeps ~0.9°/pt, so the fine step made every mouse position a distinct cache
    /// entry: jitter never deduped and one sweep evicted the whole 160-entry cache. A quarter of a
    /// degree is well under a pixel of silhouette movement at the 1024 px canvas cap, but it is
    /// ~4 px at the 4096 px offscreen budget — and two deliberately different poses must never
    /// export pixel-identical.
    static let snapshotAngleStep: Double = 0.25
}
