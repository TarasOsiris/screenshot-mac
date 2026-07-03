#if os(iOS)
import SwiftUI
import UIKit

struct InlineTextEditor: View {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var verticalAlignment: TextVerticalAlign = .center
    var uppercase: Bool = false
    var letterSpacing: CGFloat? = nil
    var lineHeightMultiple: CGFloat? = nil
    var legacyLineSpacing: CGFloat? = nil
    var richTextData: String? = nil
    var renderScale: CGFloat = 1
    var formatController: RichTextFormatController? = nil
    var onCommit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)? = nil
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)? = nil

    var body: some View {
        UITextViewEditor(
            text: $text,
            font: font,
            color: color,
            alignment: alignment,
            verticalAlignment: verticalAlignment,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData,
            renderScale: renderScale,
            formatController: formatController,
            onCommit: onCommit,
            onRichTextChange: onRichTextChange,
            onSelectionChange: onSelectionChange
        )
    }
}
#endif
