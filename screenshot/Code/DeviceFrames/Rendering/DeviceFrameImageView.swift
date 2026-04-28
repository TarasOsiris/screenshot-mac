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

        // Bleed the screenshot 1pt past the spec'd aperture on every side so the
        // anti-aliased edge of the bezel PNG blends with the screenshot rather than
        // whatever sits behind the frame. Without this, light canvas backgrounds
        // show through as a 1px halo on the iPhone 17 family.
        let bleed: CGFloat = 1
        let cornerRadius = height * spec.cornerRadiusFraction + bleed
        let bottomCornerRadius = frame.fallbackCategory == .macbook ? 0 : cornerRadius

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
                width: width * (1 - spec.leftFraction - spec.rightFraction) + bleed * 2,
                height: height * (1 - spec.topFraction - spec.bottomFraction) + bleed * 2
            )
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: bottomCornerRadius,
                bottomTrailingRadius: bottomCornerRadius,
                topTrailingRadius: cornerRadius,
                style: .continuous
            ))
            .offset(
                x: width * spec.leftFraction - bleed,
                y: height * spec.topFraction - bleed
            )

            if let frameImage {
                let baseImage = Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)

                if frame.isLandscapeRotation {
                    baseImage
                        .frame(width: height, height: width)
                        .rotationEffect(.degrees(90))
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

        guard let image = NSImage(named: imageName) else { return nil }
        frameImageCache.setObject(image, forKey: key)
        return image
    }
}
