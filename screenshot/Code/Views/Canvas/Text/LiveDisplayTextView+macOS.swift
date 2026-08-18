#if os(macOS)
import SwiftUI

struct LiveDisplayTextView: NSViewRepresentable {
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

    func makeNSView(context: Context) -> TextLayoutNSView {
        let view = TextLayoutNSView(frame: .zero)
        view.configure(
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
        )
        return view
    }

    func updateNSView(_ view: TextLayoutNSView, context: Context) {
        view.configure(
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
        )
    }
}
#endif
