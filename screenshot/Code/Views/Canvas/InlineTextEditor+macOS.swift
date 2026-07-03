#if os(macOS)
import SwiftUI

struct InlineTextEditor: NSViewRepresentable {
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
    var renderScale: CGFloat = 1  // macOS renders at model scale (selection is mouse-based)
    var formatController: RichTextFormatController? = nil
    var onCommit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)? = nil
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)? = nil

    private var isRichTextMode: Bool {
        richTextData != nil || formatController?.shouldEncodeRichText == true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> CenteringScrollView {
        let textView = CommitTextView()
        textView.isRichText = true
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = font
        textView.textColor = color
        textView.alignment = alignment
        textView.delegate = context.coordinator
        textView.onCommit = onCommit
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.layoutManager?.delegate = context.coordinator.compactDelegate
        applyTextStyle(to: textView, preserveSelection: false)
        if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }

        let scrollView = CenteringScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        scrollView.autohidesScrollers = true
        scrollView.centerTextView = textView
        scrollView.verticalAlignment = verticalAlignment

        formatController?.textView = textView
        formatController?.undoManager = context.coordinator.editingUndoManager
        textView.formatController = formatController

        DispatchQueue.main.async { [weak textView, weak scrollView] in
            // The editor may have been dismissed (commit/esc) before this runs;
            // bail if the views are gone or detached from a window so we don't
            // steal first responder back to a view that's being torn down.
            guard let textView, let scrollView, textView.window != nil else { return }
            scrollView.centerDocumentView()
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }

        return scrollView
    }

    static func dismantleNSView(_ scrollView: CenteringScrollView, coordinator: Coordinator) {
        // Drop undo steps that target the text view before it's freed, so a later
        // undo: can never invoke a step against a dangling NSTextView pointer.
        coordinator.editingUndoManager.removeAllActions()
        // Clear the (weak) format-controller back-reference if it still points
        // at the text view being torn down.
        if let textView = scrollView.documentView as? NSTextView,
           coordinator.parent.formatController?.textView === textView {
            coordinator.parent.formatController?.textView = nil
            coordinator.parent.formatController?.undoManager = nil
        }
    }

    func updateNSView(_ scrollView: CenteringScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        formatController?.textView = textView
        formatController?.undoManager = context.coordinator.editingUndoManager

        // In rich text mode, don't rebuild the attributed string on every update
        // to avoid destroying per-range formatting during editing.
        let shouldPreserveRichTextStorage = isRichTextMode
            && (
                context.coordinator.hasPendingRichTextEdit(matching: richTextData)
                || formatController?.hasPendingTypingAttributes == true
            )

        // Never replace the text storage while the user is mid-IME-composition
        // (marked text present) — doing so collapses the composition and the
        // insertion point.
        if shouldPreserveRichTextStorage || textView.hasMarkedText() {
            if let delegate = textView.layoutManager?.delegate as? CompactLineLayoutDelegate {
                delegate.lineHeightMultiple = lineHeightMultiple ?? TextLayoutStyle.defaultLineHeightMultiple
            }
            let glyphPadding = TextLayoutStyle.editorVerticalPadding(
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing,
                font: font
            )
            (textView as? CommitTextView)?.verticalGlyphPadding = glyphPadding
        } else {
            applyTextStyle(to: textView)
        }

        if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
        scrollView.verticalAlignment = verticalAlignment
        scrollView.centerDocumentView()
    }

    private func applyTextStyle(to textView: NSTextView, preserveSelection: Bool = true) {
        if let delegate = textView.layoutManager?.delegate as? CompactLineLayoutDelegate {
            delegate.lineHeightMultiple = lineHeightMultiple ?? TextLayoutStyle.defaultLineHeightMultiple
        }
        let selectedRanges = textView.selectedRanges
        let attributes = TextLayoutStyle.textAttributes(
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            includeBaselineOffset: false,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing
        )
        let glyphPadding = TextLayoutStyle.editorVerticalPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )

        if let storage = textView.textStorage {
            let newString = RichTextUtils.buildAttributedString(
                richText: richTextData,
                plainText: text,
                font: font,
                color: color,
                alignment: alignment,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing,
                uppercase: uppercase
            )
            // Skip the disruptive replace when the rendered result is identical
            // (the common case while typing, since `text` is fed back from the
            // text view) — avoids needless cursor/IME churn on every update.
            if !storage.isEqual(to: newString) {
                storage.setAttributedString(newString)
            }
        } else {
            textView.string = uppercase ? text.uppercased() : text
        }

        textView.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
        textView.typingAttributes = attributes
        (textView as? CommitTextView)?.verticalGlyphPadding = glyphPadding

        if preserveSelection {
            textView.selectedRanges = selectedRanges
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineTextEditor
        let compactDelegate = CompactLineLayoutDelegate()
        var hasReceivedTextChange = false
        var lastEmittedRichTextData: String?

        // Isolate inline-edit undo (typing + formatting) from the document/window undo
        // manager. Without this NSTextView falls back to the window's manager — the same
        // one AppState drives — so edit steps interleave with document undo and outlive
        // the text view: a later document-level undo: invokes a step whose freed NSTextView
        // target has been reused, crashing with a bad cast. Cleared on teardown.
        let editingUndoManager = UndoManager()

        func undoManager(for view: NSTextView) -> UndoManager? { editingUndoManager }

        init(_ parent: InlineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            hasReceivedTextChange = true
            let maxLength = 5000
            if textView.string.count > maxLength, let storage = textView.textStorage {
                let excess = NSRange(location: maxLength, length: storage.length - maxLength)
                storage.deleteCharacters(in: excess)
            }
            if parent.uppercase && !parent.isRichTextMode {
                let uppercased = textView.string.uppercased()
                if textView.string != uppercased {
                    let selectedRanges = textView.selectedRanges
                    textView.string = uppercased
                    textView.selectedRanges = selectedRanges
                }
            }
            parent.text = textView.string
            parent.formatController?.clearPendingTypingAttributes()

            if parent.formatController?.pendingClearFormatting == true {
                parent.formatController?.pendingClearFormatting = false
                lastEmittedRichTextData = nil
                parent.onRichTextChange?(nil, textView.string)
            } else if parent.isRichTextMode {
                if textView.string.isEmpty {
                    lastEmittedRichTextData = nil
                    parent.onRichTextChange?(nil, "")
                } else if let storage = textView.textStorage,
                          let encoded = RichTextUtils.encode(storage) {
                    lastEmittedRichTextData = encoded
                    parent.onRichTextChange?(encoded, textView.string)
                }
            } else {
                textView.typingAttributes = TextLayoutStyle.textAttributes(
                    font: parent.font,
                    color: parent.color,
                    alignment: parent.alignment,
                    letterSpacing: parent.letterSpacing,
                    includeBaselineOffset: false,
                    lineHeightMultiple: parent.lineHeightMultiple,
                    legacyLineSpacing: parent.legacyLineSpacing
                )
            }

            if let scrollView = textView.enclosingScrollView as? CenteringScrollView {
                if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
                scrollView.centerDocumentView()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let selection = textView.selectedRange()
            let (attrs, range): ([NSAttributedString.Key: Any]?, NSRange?) = selection.length > 0
                ? (textView.textStorage?.attributes(at: selection.location, effectiveRange: nil), selection)
                : (textView.typingAttributes, nil)
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChange?(attrs, range)
            }
        }

        func hasPendingRichTextEdit(matching richTextData: String?) -> Bool {
            hasReceivedTextChange && richTextData == lastEmittedRichTextData
        }
    }
}

#endif
