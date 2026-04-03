import AppKit
import SwiftUI

struct DeviceFrameImageView: View {
    private static let frameImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        return cache
    }()

    let frame: DeviceFrame
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?

    var body: some View {
        let spec = frame.spec
        let frameImage = frame.imageName.flatMap(Self.cachedFrameImage(named:))

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
            .frame(
                width: width * (1 - spec.leftFraction - spec.rightFraction),
                height: height * (1 - spec.topFraction - spec.bottomFraction)
            )
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: height * spec.cornerRadiusFraction,
                bottomLeadingRadius: frame.fallbackCategory == .macbook ? 0 : height * spec.cornerRadiusFraction,
                bottomTrailingRadius: frame.fallbackCategory == .macbook ? 0 : height * spec.cornerRadiusFraction,
                topTrailingRadius: height * spec.cornerRadiusFraction,
                style: .continuous
            ))
            .offset(
                x: width * spec.leftFraction,
                y: height * spec.topFraction
            )

            if let frameImage {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
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

        guard let image = NSImage(named: imageName) else { return nil }
        frameImageCache.setObject(image, forKey: key)
        return image
    }
}
