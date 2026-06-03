#if os(iOS)
import UIKit
import SwiftUI

// The slice of NSImage's API the codebase calls, mapped onto UIImage. Heavy AppKit drawing
// (lockFocus, NSGraphicsContext compositing) is NOT shimmed here — those call sites are
// guarded with `#if os(macOS)` and stubbed on iOS for this foundation pass.
extension UIImage {
    convenience init?(contentsOf url: URL) {
        self.init(contentsOfFile: url.path)
    }

    /// A blank transparent image of the given size. On macOS `NSImage(size:)` yields an empty
    /// canvas that callers draw into; on iOS the draw-into call sites are guarded, so this is
    /// only used for placeholder/empty images.
    convenience init(size: CGSize) {
        let safe = (size.width > 0 && size.height > 0) ? size : CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: safe)
        let img = renderer.image { _ in }
        self.init(cgImage: img.cgImage!, scale: img.scale, orientation: .up)
    }

    convenience init(cgImage: CGImage, size: CGSize) {
        // Honor the requested logical size by deriving a scale from the pixel dimensions, so
        // `.size` matches macOS NSImage semantics (cropImage reads cgImage.width / size.width to
        // recover the pixel ratio — passing scale through keeps that correct when the source was
        // rendered below 1x, e.g. an ImageRenderer output capped to the GPU texture limit).
        let scale = size.width > 0 ? CGFloat(cgImage.width) / size.width : 1
        self.init(cgImage: cgImage, scale: max(scale, 0.0001), orientation: .up)
    }

    func cgImage(forProposedRect rect: UnsafeMutablePointer<CGRect>?, context: Any?, hints: [AnyHashable: Any]?) -> CGImage? {
        cgImage
    }

    var tiffRepresentation: Data? { pngData() }

    var pixelsWide: Int { cgImage?.width ?? Int((size.width * scale).rounded()) }
    var pixelsHigh: Int { cgImage?.height ?? Int((size.height * scale).rounded()) }

    /// NSImage exposes multiple `NSImageRep`s; on iOS a UIImage is its own single rep, so the
    /// `image.representations.first` pattern (used only to read pixel dimensions) returns self.
    var representations: [UIImage] { [self] }

    var isValid: Bool { cgImage != nil || ciImage != nil }
}

extension Image {
    /// `Image(nsImage:)` is macOS-only in SwiftUI; map it to `Image(uiImage:)` on iOS so the
    /// (NSImage = UIImage) call sites compile unchanged.
    init(nsImage: UIImage) {
        self.init(uiImage: nsImage)
    }
}
#endif
