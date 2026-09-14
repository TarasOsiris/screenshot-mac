#if os(macOS)
import AppKit
#else
import UIKit
#endif
import os
import SwiftUI

struct DeviceFrameImageView: View {
    private static let frameImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        // A bezel costs its decoded bitmap, not its file size — the largest is ~22 MB, so
        // countLimit alone would let 50 of them pin over a gigabyte.
        cache.totalCostLimit = DeviceModelRenderer.decodedImageCacheByteLimit
        return cache
    }()

    let frame: DeviceFrame
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?

    var body: some View {
        let spec = frame.spec
        let frameImage = frame.imageName.flatMap(Self.cachedFrameImage(named:))

        // Bleed the screenshot 1pt past the spec'd aperture on every side so the
        // anti-aliased edge of the bezel PNG blends with the screenshot rather than
        // whatever sits behind the frame. Without this, light canvas backgrounds
        // show through as a 1px halo on the iPhone 17 family.
        let bleed: CGFloat = 1
        let screen = spec.screenRect(in: CGSize(width: width, height: height)).insetBy(dx: -bleed, dy: -bleed)

        ZStack(alignment: .topLeading) {
            Group {
                if let screenshotImage {
                    Image(nsImage: screenshotImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Color.white
                }
            }
            .frame(width: screen.width, height: screen.height)
            .clipShape(UnevenRoundedRectangle(
                cornerRadii: spec.clipCornerRadii(height: height, bleed: bleed),
                style: .continuous
            ))
            .offset(x: screen.minX, y: screen.minY)

            if let frameImage {
                let baseImage = Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)

                if let rotationDegrees = frame.landscapeRotationDegrees {
                    baseImage
                        .frame(width: height, height: width)
                        .rotationEffect(.degrees(rotationDegrees))
                        .frame(width: width, height: height)
                } else {
                    baseImage
                        .frame(width: width, height: height)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
    }

    private static func cachedFrameImage(named imageName: String) -> NSImage? {
        let key = imageName as NSString
        if let cached = frameImageCache.object(forKey: key) {
            return cached
        }

        guard let image = NSImage(named: imageName) else {
            AppLogger.export.warning("Device bezel asset missing: \(imageName, privacy: .public)")
            return nil
        }
        frameImageCache.setObject(image, forKey: key, cost: decodedByteCost(of: image))
        return image
    }

    /// `pixelsWide`/`pixelsHigh`/`representations` are shimmed onto `UIImage` (Platform/PlatformImageShims.swift),
    /// so this reads decoded pixel dimensions identically on both platforms without an `#if os`.
    private static func decodedByteCost(of image: NSImage) -> Int {
        let pixels = image.representations.lazy
            .map { $0.pixelsWide * $0.pixelsHigh }
            .max() ?? Int(image.size.width * image.size.height)
        return pixels * 4
    }
}
