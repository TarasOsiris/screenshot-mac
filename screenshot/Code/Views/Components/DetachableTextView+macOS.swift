#if os(macOS)
import AppKit

/// An `NSTextView` that SwiftUI can tear down while it still holds a selection.
class DetachableTextView: NSTextView {
    // A Writing Tools affordance outlives the selection that scheduled it, so clicking one after
    // SwiftUI tore this editor down popped its popover on a window-less view (SCREENSHOT-BRO-1D).
    // Nothing retracts a scheduled affordance, and `.limited` still shows one — only `.none` does.
    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        writingToolsBehavior = .none
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        writingToolsBehavior = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        writingToolsBehavior = .none
    }

    /// Give anything holding this view by its selection a chance to unwind before it is freed.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            if window?.firstResponder === self { window?.makeFirstResponder(nil) }
            setSelectedRange(NSRange(location: 0, length: 0))
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
#endif
