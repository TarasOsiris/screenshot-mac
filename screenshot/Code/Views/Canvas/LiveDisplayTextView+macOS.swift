#if os(macOS)
import SwiftUI

struct LiveDisplayTextView: NSViewRepresentable {
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
