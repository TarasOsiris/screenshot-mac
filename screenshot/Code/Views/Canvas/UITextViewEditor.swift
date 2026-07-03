#if os(iOS)
import SwiftUI
import UIKit

struct UITextViewEditor: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont
    var color: UIColor
    var alignment: NSTextAlignment
    var verticalAlignment: TextVerticalAlign
    var uppercase: Bool
    var letterSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?
    var legacyLineSpacing: CGFloat?
    var richTextData: String?
    var renderScale: CGFloat
    var formatController: RichTextFormatController?
    var onCommit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)?
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)?

    private var isRichTextMode: Bool {
        richTextData != nil || formatController?.shouldEncodeRichText == true
    }

    private var scaledFont: UIFont { renderScale == 1 ? font : font.withSize(font.pointSize * renderScale) }
    private var scaledLetterSpacing: CGFloat? { letterSpacing.map { $0 * renderScale } }
    private var scaledLegacyLineSpacing: CGFloat? { legacyLineSpacing.map { $0 * renderScale } }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> VerticalAlignTextView {
        let textView = VerticalAlignTextView()
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.layoutManager.delegate = context.coordinator.compactDelegate
        textView.delegate = context.coordinator
        textView.isScrollEnabled = false
        textView.allowsEditingTextAttributes = true

        textView.attributedText = buildAttributedText()
        textView.typingAttributes = baseTypingAttributes()
        applyVerticalLayout(to: textView, context: context)

        formatController?.textView = textView
        formatController?.renderScale = renderScale
        context.coordinator.lastRenderScale = renderScale

        DispatchQueue.main.async {
            textView.becomeFirstResponder()
            textView.selectAll(nil)
        }
        return textView
    }

    func updateUIView(_ textView: VerticalAlignTextView, context: Context) {
        context.coordinator.parent = self
        formatController?.textView = textView
        formatController?.renderScale = renderScale

        let previousScale = context.coordinator.lastRenderScale
        context.coordinator.lastRenderScale = renderScale

        if isRichTextMode || textView.markedTextRange != nil {
            if previousScale != renderScale, previousScale > 0, textView.markedTextRange == nil {
                let selection = textView.selectedRange
                textView.attributedText = textView.attributedText.scaledFontMetrics(by: renderScale / previousScale)
                textView.selectedRange = selection
            }
            applyVerticalLayout(to: textView, context: context)
            return
        }

        let newAttr = buildAttributedText()
        if !textView.attributedText.isEqual(to: newAttr) {
            let selection = textView.selectedRange
            textView.attributedText = newAttr
            textView.selectedRange = selection
        }
        textView.typingAttributes = baseTypingAttributes()
        applyVerticalLayout(to: textView, context: context)
    }

    private func buildAttributedText() -> NSAttributedString {
        RichTextUtils.buildAttributedString(
            richText: richTextData,
            plainText: text,
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            uppercase: uppercase
        ).scaledFontMetrics(by: renderScale)
    }

    private func baseTypingAttributes() -> [NSAttributedString.Key: Any] {
        TextLayoutStyle.textAttributes(
            font: scaledFont,
            color: color,
            alignment: alignment,
            letterSpacing: scaledLetterSpacing,
            includeBaselineOffset: false,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: scaledLegacyLineSpacing
        )
    }

    private func applyVerticalLayout(to textView: VerticalAlignTextView, context: Context) {
        context.coordinator.compactDelegate.lineHeightMultiple = lineHeightMultiple ?? TextLayoutStyle.defaultLineHeightMultiple
        textView.verticalAlignment = verticalAlignment
        textView.glyphPadding = TextLayoutStyle.verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: scaledLegacyLineSpacing,
            font: scaledFont
        )
        textView.setNeedsLayout()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VerticalAlignTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width != .infinity, height != .infinity else { return nil }
        return CGSize(width: width, height: height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: UITextViewEditor
        let compactDelegate = CompactLineLayoutDelegate()
        var lastRenderScale: CGFloat = 1
        init(_ parent: UITextViewEditor) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            if parent.uppercase, !parent.isRichTextMode {
                let upper = textView.text.uppercased()
                if textView.text != upper {
                    let selection = textView.selectedRange
                    textView.text = upper
                    textView.selectedRange = selection
                }
            }
            textView.setNeedsLayout()
            parent.text = textView.text
            parent.formatController?.clearPendingTypingAttributes()

            if parent.formatController?.pendingClearFormatting == true {
                parent.formatController?.pendingClearFormatting = false
                parent.onRichTextChange?(nil, textView.text)
            } else if parent.isRichTextMode {
                if textView.text.isEmpty {
                    parent.onRichTextChange?(nil, "")
                } else if let encoded = RichTextUtils.encode(
                    textView.textStorage.scaledFontMetrics(by: 1 / parent.renderScale)
                ) {
                    parent.onRichTextChange?(encoded, textView.text)
                }
            }
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            let selection = textView.selectedRange
            let (rawAttrs, range): ([NSAttributedString.Key: Any]?, NSRange?) = selection.length > 0
                ? (textView.textStorage.attributes(at: selection.location, effectiveRange: nil), selection)
                : (textView.typingAttributes, nil)
            let attrs = modelScaledAttributes(rawAttrs, renderScale: parent.renderScale)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.parent.formatController?.setSelectionState(
                    RichTextSelectionState(from: attrs, hasRangeSelection: range != nil)
                )
                self.parent.onSelectionChange?(attrs, range)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onCommit()
        }
    }
}
#endif
