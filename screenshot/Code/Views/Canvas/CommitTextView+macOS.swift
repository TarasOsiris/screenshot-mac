#if os(macOS)
import AppKit

final class CommitTextView: NSTextView {
    var onCommit: (() -> Void)?
    var verticalGlyphPadding: CGFloat = 0
    weak var formatController: RichTextFormatController?

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
