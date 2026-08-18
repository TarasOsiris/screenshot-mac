#if os(iOS)
import SwiftUI
import UIKit

struct LiveDisplayTextView: View {
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

    var body: some View {
        RasterizedDisplayTextView(
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
