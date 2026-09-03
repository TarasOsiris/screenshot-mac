#if os(macOS)
import AppKit

final class CommitTextView: NSTextView {
    var onCommit: (() -> Void)?
    var verticalGlyphPadding: CGFloat = 0
    weak var formatController: RichTextFormatController?

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

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            onCommit?()
            return
        }
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let action = Self.formatAction(for: event) {
            formatController?.applyAction(action)
            return
        }
        super.keyDown(with: event)
    }

    private static func formatAction(for event: NSEvent) -> RichTextFormatAction? {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b": return .toggleBold
        case "i": return .toggleItalic
        case "u": return .toggleUnderline
        default:  return nil
        }
    }
}
#endif
