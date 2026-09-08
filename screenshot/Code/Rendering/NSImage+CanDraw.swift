#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension NSImage {
    /// Whether this image can actually contribute pixels to a composite.
    ///
    /// An image can exist, be non-nil, report a size and still draw nothing — no representation, a
    /// zero-sized one, or one no `CGImage` can be made from. The render paths draw whatever they
    /// are handed and leave a hole when that happens, so every presence check upstream passes
    /// while the output is blank. `RowRenderContext` uses this to tell that case apart from a
    /// resource that was simply absent.
    var canDraw: Bool {
        guard size.width > 0, size.height > 0 else { return false }
        #if os(macOS)
        guard representations.contains(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) else { return false }
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil) != nil
        #else
        // `NSImage` is `UIImage` here (see PlatformAliases): backed by a CGImage or a CIImage,
        // either of which draws, and neither of which exposes representations.
        return cgImage != nil || ciImage != nil
        #endif
    }
}
