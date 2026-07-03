#if os(macOS)
import AppKit

class CenteringScrollView: NSScrollView {
    weak var centerTextView: NSTextView?
    var verticalAlignment: TextVerticalAlign = .center

    func centerDocumentView() {
        guard let textView = centerTextView else { return }
        guard let tc = textView.textContainer else { return }
        let glyphPadding = (textView as? CommitTextView)?.verticalGlyphPadding ?? 0
        let textHeight = textView.layoutManager?.usedRect(for: tc).height ?? 0
        let paddedTextHeight = textHeight + glyphPadding
        let viewHeight = contentSize.height
        let targetHeight = max(viewHeight, paddedTextHeight)
        let targetSize = NSSize(width: contentSize.width, height: targetHeight)
        if textView.frame.size != targetSize {
            textView.setFrameSize(targetSize)
        }
        if paddedTextHeight < viewHeight {
            let topInset: CGFloat
            switch verticalAlignment {
            case .top:
                topInset = glyphPadding
            case .center:
                topInset = glyphPadding + ((viewHeight - paddedTextHeight) / 2)
            case .bottom:
                topInset = glyphPadding + (viewHeight - paddedTextHeight)
            }
            textView.textContainerInset = NSSize(width: 0, height: topInset)
        } else {
            textView.textContainerInset = NSSize(width: 0, height: glyphPadding)
        }
    }

    override func layout() {
        super.layout()
        centerDocumentView()
    }
}
#endif
