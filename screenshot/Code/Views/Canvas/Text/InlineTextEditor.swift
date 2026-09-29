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
    var fontScale: CGFloat = 1
    var stroke: TextStroke?
    var glyphFill: TextGlyphFill?
    /// Supersample factor for the raster. Export and preview leave it at the default, which
    /// reproduces what the implicit rasterizer produced before; the editor passes its on-screen
    /// scale so a zoomed-in row stays sharp.
    var renderScale: CGFloat = TextLayoutStyle.defaultTextRenderScale
    /// False only while the shape is under a live continuous edit, whose per-tick rasters are
    /// intermediates the shared cache would keep at the expense of every settled entry.
    var cachesRaster = true

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
            fontScale: fontScale,
            stroke: stroke,
            glyphFill: glyphFill,
            renderScale: renderScale,
            cachesResult: cachesRaster
        ) {
            // An outline is rasterized into a margin around the box; hang it outside the frame.
            let pad = stroke?.rasterPadding ?? 0
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width + 2 * pad, height: size.height + 2 * pad)
                .padding(-pad)
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
