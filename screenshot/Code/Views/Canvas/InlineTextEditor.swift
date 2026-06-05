import SwiftUI
#if os(iOS)
import UIKit
#endif


struct RasterizedDisplayTextView: View {
    var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var verticalAlignment: TextVerticalAlign
    var uppercase: Bool = false
    var letterSpacing: CGFloat? = nil
    var lineHeightMultiple: CGFloat? = nil
    var legacyLineSpacing: CGFloat? = nil
    var richTextData: String? = nil

    var body: some View {
        GeometryReader { proxy in
            if let image = TextLayoutStyle.renderImage(
                size: proxy.size,
                text: text,
                font: font,
                color: color,
                alignment: alignment,
                verticalAlignment: verticalAlignment,
                uppercase: uppercase,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing,
                richTextData: richTextData
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color.clear
            }
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
