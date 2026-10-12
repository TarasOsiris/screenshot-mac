import SwiftUI

/// Multi-line plain-text editor. On macOS its undo stack dies with it, unlike `TextEditor`'s, which
/// outlives the view on the window (SCREENSHOT-BRO-2F); iOS keeps `TextEditor`.
struct PlainTextEditor {
    @Binding var text: String
    var font: NSFont
    /// Off for code: no smart quotes or dashes, autocorrect or text replacement.
    var substitutesText = true
    #if os(macOS)
    var isFocused: Binding<Bool>?
    #endif
}

#if os(macOS)
extension PlainTextEditor: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = FocusReportingTextView()
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = font
        textView.string = text
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = substitutesText
        textView.isAutomaticDashSubstitutionEnabled = substitutesText
        textView.isAutomaticSpellingCorrectionEnabled = substitutesText
        textView.isAutomaticTextReplacementEnabled = substitutesText
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.onFocusChange = { [weak coordinator = context.coordinator] in coordinator?.focusChanged($0) }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        guard let textView = scrollView.documentView as? FocusReportingTextView else { return }
        if textView.font != font { textView.font = font }
        // Never replace the storage mid-IME composition; the next update catches up.
        if textView.string != text, !textView.hasMarkedText() {
            textView.string = text
            // The stack's ranges describe the text that was just replaced.
            coordinator.editingUndoManager.removeAllActions()
        }
        // Act on changes of the binding only, so an update carrying a value from before the
        // user's own click can't pull focus back out.
        if let wantsFocus = isFocused?.wrappedValue, wantsFocus != coordinator.lastFocusRequest {
            coordinator.lastFocusRequest = wantsFocus
            textView.requestFocus(wantsFocus)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        (scrollView.documentView as? FocusReportingTextView)?.onFocusChange = nil
        coordinator.editingUndoManager.removeAllActions()
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: PlainTextEditor
        var lastFocusRequest: Bool?
        // Not the window's: that stack outlives this view and doesn't retain the steps' target.
        let editingUndoManager = UndoManager()

        init(_ parent: PlainTextEditor) {
            self.parent = parent
        }

        func undoManager(for view: NSTextView) -> UndoManager? { editingUndoManager }

        // Not `textDidChange`: AppKit doesn't send it for undo and redo.
        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), parent.text != textStorage.string else { return }
            parent.text = textStorage.string
        }

        // First-responder changes can land mid-update (a view leaving the window), where
        // writing SwiftUI state is not allowed.
        func focusChanged(_ focused: Bool) {
            DispatchQueue.main.async { [weak self] in
                guard let isFocused = self?.parent.isFocused, isFocused.wrappedValue != focused else { return }
                isFocused.wrappedValue = focused
            }
        }
    }
}

private final class FocusReportingTextView: DetachableTextView {
    var onFocusChange: ((Bool) -> Void)?
    private var pendingFocus: Bool?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocusChange?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { onFocusChange?(false) }
        return accepted
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pendingFocus { requestFocus(pendingFocus) }
    }

    /// Applied on the next turn: called from a SwiftUI update, and a view not yet in a window
    /// can't take focus until it is.
    func requestFocus(_ focused: Bool) {
        guard window != nil else {
            pendingFocus = focused
            return
        }
        pendingFocus = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let isFirstResponder = window.firstResponder === self
            if focused, !isFirstResponder {
                window.makeFirstResponder(self)
            } else if !focused, isFirstResponder {
                window.makeFirstResponder(nil)
            }
        }
    }
}
#else
extension PlainTextEditor: View {
    var body: some View {
        // swiftlint:disable:next swiftui_text_editor
        TextEditor(text: $text)
            .font(Font(font))
            .autocorrectionDisabled(!substitutesText)
            .textInputAutocapitalization(substitutesText ? nil : .never)
    }
}
#endif
