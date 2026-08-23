#if os(iOS)
import UIKit

final class VerticalAlignTextView: UITextView {
    var verticalAlignment: TextVerticalAlign = .center
    var glyphPadding: CGFloat = 0

    /// Typing and formatting undo stay on a stack this view owns, never the responder chain's.
    /// `registerUndo(withTarget:)` doesn't retain its target, so a step registered against this
    /// view on a longer-lived manager would outlive it and crash a later undo.
    private let editingUndoManager = UndoManager()

    override var undoManager: UndoManager? { editingUndoManager }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let topInset = TextLayoutStyle.verticalOffset(
            containerHeight: bounds.height,
            contentHeight: usedHeight,
            padding: glyphPadding,
            alignment: verticalAlignment
        )
        if abs(textContainerInset.top - topInset) > 0.5 {
            textContainerInset = UIEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
        }
    }
}
#endif
