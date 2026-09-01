import SwiftUI
#if os(iOS)
import UIKit
#endif

struct RasterizedDisplayTextView: View {
    /// Pass the enclosing frame explicitly on the export/snapshot path — a GeometryReader's
    /// size-dependent child isn't reliably resolved before an offscreen capture, which leaves
    /// text blank intermittently (same gotcha as `BackgroundRendering`). nil (the live iOS
    /// canvas) falls back to reading the on-screen frame.
    var size: CGSize?
    var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var verticalAlignment: TextVerticalAlign
    var uppercase: Bool = false
    var letterSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?
    var legacyLineSpacing: CGFloat?
    var richTextData: String?
    /// Supersample factor for the raster. Export and preview leave it at the default, which
    /// reproduces what the implicit rasterizer produced before; the editor passes its on-screen
    /// scale so a zoomed-in row stays sharp.
    var renderScale: CGFloat = TextLayoutStyle.defaultTextRenderScale

    var body: some View {
        if let size {
            textImage(size: size)
        } else {
            GeometryReader { proxy in
                textImage(size: proxy.size)
            }
        }
    }

    @ViewBuilder
    private func textImage(size: CGSize) -> some View {
        if let image = TextLayoutStyle.renderImage(
            size: size,
            text: text,
            font: font,
            color: color,
            alignment: alignment,
            verticalAlignment: verticalAlignment,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData,
            renderScale: renderScale
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
        } else {
            Color.clear
        }
    }
}

extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

extension Optional where Wrapped == TextAlign {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .right: return .right
        case .center, .none: return .center
        }
    }
}
