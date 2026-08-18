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
    var letterSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?
    var legacyLineSpacing: CGFloat?
    var richTextData: String?
    var renderScale: CGFloat = 1
    var formatController: RichTextFormatController?
    var onCommit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)?
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)?

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
