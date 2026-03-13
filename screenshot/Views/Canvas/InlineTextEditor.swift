import SwiftUI

struct InlineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var uppercase: Bool = false
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CenteringScrollView {
        let textView = CommitTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = font
        textView.textColor = color
        textView.alignment = alignment
        textView.string = uppercase ? text.uppercased() : text
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }

        let scrollView = CenteringScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true
        scrollView.centerTextView = textView

        DispatchQueue.main.async {
            scrollView.centerDocumentView()
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: CenteringScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let displayText = uppercase ? text.uppercased() : text
        if textView.string != displayText {
            textView.string = displayText
        }
        textView.font = font
        textView.textColor = color
        textView.alignment = alignment
        if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
        scrollView.centerDocumentView()
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor

        init(_ parent: InlineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let maxLength = 5000
            if textView.string.count > maxLength {
                textView.string = String(textView.string.prefix(maxLength))
            }
            if parent.uppercase {
                let uppercased = textView.string.uppercased()
                if textView.string != uppercased {
                    let selectedRanges = textView.selectedRanges
                    textView.string = uppercased
                    textView.selectedRanges = selectedRanges
                }
            }
            parent.text = textView.string
            if let scrollView = textView.enclosingScrollView as? CenteringScrollView {
                if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
                scrollView.centerDocumentView()
            }
        }
    }
}

class CenteringScrollView: NSScrollView {
    weak var centerTextView: NSTextView?

    func centerDocumentView() {
        guard let textView = centerTextView else { return }
        guard let tc = textView.textContainer else { return }
        let textHeight = textView.layoutManager?.usedRect(for: tc).height ?? 0
        let viewHeight = contentSize.height
        if textHeight < viewHeight {
            let topInset = (viewHeight - textHeight) / 2
            textView.textContainerInset = NSSize(width: 0, height: topInset)
        } else {
            textView.textContainerInset = .zero
        }
    }

    override func layout() {
        super.layout()
        centerDocumentView()
    }
}

private class CommitTextView: NSTextView {
    var onCommit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            // Return without shift -> commit
            onCommit?()
            return
        }
        if event.keyCode == 53 {
            // Escape -> commit
            onCommit?()
            return
        }
        super.keyDown(with: event)
    }
}

extension Font.Weight {
    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

extension Optional where Wrapped == TextAlign {
    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .right: return .right
        case .center, .none: return .center
        }
    }
}
