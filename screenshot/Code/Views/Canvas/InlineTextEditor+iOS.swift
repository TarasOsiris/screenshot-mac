#if os(iOS)
import Combine
import SwiftUI
import UIKit

/// iPad renders live canvas text through the same rasterized path as preview (TextKit →
/// image) for this foundation pass — no live NSView.
struct LiveDisplayTextView: View {
    var text: String
    var font: NSFont
    var color: NSColor
    var alignment: NSTextAlignment
    var verticalAlignment: TextVerticalAlign
    var uppercase: Bool = false
    var letterSpacing: CGFloat? = nil
    var lineHeightMultiple: CGFloat? = nil
    var legacyLineSpacing: CGFloat? = nil
    var richTextData: String? = nil

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
// MARK: - iOS text editing

/// iPad inline text editor backed by UITextView, with per-range rich-text formatting
/// (bold/italic/underline/strikethrough/size/color) applied through `RichTextFormatController`
/// and surfaced via the docked `RichTextDockedBar` above the bottom properties bar.
struct InlineTextEditor: View {
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
    var renderScale: CGFloat = 1
    var formatController: RichTextFormatController? = nil
    var onCommit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)? = nil
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)? = nil

    var body: some View {
        UITextViewEditor(
            text: $text,
            font: font,
            color: color,
            alignment: alignment,
            verticalAlignment: verticalAlignment,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            richTextData: richTextData,
            renderScale: renderScale,
            formatController: formatController,
            onCommit: onCommit,
            onRichTextChange: onRichTextChange,
            onSelectionChange: onSelectionChange
        )
    }
}

private struct UITextViewEditor: UIViewRepresentable {
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

    // The editor renders at display scale (model metrics × renderScale) so selection handles are
    // screen-sized; storage is therefore at display scale and converted back to model on encode.
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

        // The format bar is docked above the bottom properties bar in ContentView (not an
        // inputAccessoryView, which would sit below it) — here we just hand it the text view.
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

        // In rich-text mode (or mid-IME-composition) don't rebuild the attributed string or reset
        // typing attributes — that would wipe per-range formatting / pending typing styles. Still
        // keep the vertical-alignment + line-height layout in sync.
        if isRichTextMode || textView.markedTextRange != nil {
            // Zooming the canvas mid-edit changes renderScale; rescale the preserved storage so the
            // editing text keeps matching its box and the model-scale encode stays correct.
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

    /// Build the editing attributed string identically to the rendered (non-editing) display
    /// path so the text doesn't shift when editing begins (`TextLayoutStyle.renderImage`), then
    /// scale all absolute metrics by `renderScale` to render at display scale.
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

    /// Mirror the display path's line-height compression and vertical alignment so the editor is
    /// pixel-aligned with the rasterized text it replaces. Glyph padding uses the display-scale
    /// font so the alignment offset matches the (scaled-down) display image.
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

    /// Fill the proposed frame (the shape's box) rather than the text view's intrinsic
    /// single-line size — otherwise a non-scrolling UITextView lays text out on one line
    /// instead of wrapping at the box width.
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
                    // Preserve the caret/selection — uppercasing keeps character offsets, so the
                    // NSRange stays valid (UITextRange objects would be invalidated by setting text).
                    let selection = textView.selectedRange
                    textView.text = upper
                    textView.selectedRange = selection
                }
            }
            // Re-center vertically as the text block grows/shrinks (VerticalAlignTextView recomputes
            // its top inset in layoutSubviews).
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
            // Convert to model space once, so both the format bar and AppState see model-size fonts.
            let attrs = modelScaledAttributes(rawAttrs, renderScale: parent.renderScale)
            parent.formatController?.setSelectionState(RichTextSelectionState(from: attrs, hasRangeSelection: range != nil))
            DispatchQueue.main.async { [weak self] in
                self?.parent.onSelectionChange?(attrs, range)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.onCommit()
        }
    }
}

/// UITextView that vertically aligns its text block (top/center/bottom) within its bounds to match
/// the rendered display path (`TextLayoutStyle.renderImage`), via a computed top container inset —
/// UITextView otherwise pins text to the top, which would shift it when editing begins.
final class VerticalAlignTextView: UITextView {
    var verticalAlignment: TextVerticalAlign = .center
    var glyphPadding: CGFloat = 0

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

/// Applies rich-text format actions to the active iPad `UITextView` from the docked format bar.
/// Mirrors the macOS controller's behavior on UIKit text storage / typing attributes.
final class RichTextFormatController: ObservableObject {
    private(set) var shouldEncodeRichText = false
    private(set) var hasPendingTypingAttributes = false
    var pendingClearFormatting = false
    weak var textView: UITextView?
    /// Editor display scale: bar sizes are model-space, storage is display-space, so size actions
    /// multiply by this and reported sizes divide by it.
    var renderScale: CGFloat = 1
    @Published var selectionState = RichTextSelectionState()

    func beginRichTextSession() {
        guard !shouldEncodeRichText else { return }
        shouldEncodeRichText = true
    }

    func resetRichTextSession() {
        guard shouldEncodeRichText else { return }
        shouldEncodeRichText = false
        hasPendingTypingAttributes = false
    }

    func clearPendingTypingAttributes() {
        hasPendingTypingAttributes = false
    }

    func applyAction(_ action: RichTextFormatAction) {
        guard let textView else { return }
        let storage = textView.textStorage
        let range = textView.selectedRange
        let priorShouldEncode = shouldEncodeRichText

        if range.length > 0 {
            let prior = NSAttributedString(attributedString: storage)
            shouldEncodeRichText = true
            storage.beginEditing()
            switch action {
            case .toggleBold:
                toggleFontTrait(.traitBold, range: range, storage: storage)
            case .toggleItalic:
                toggleFontTrait(.traitItalic, range: range, storage: storage)
            case .toggleUnderline:
                let current = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
                storage.addAttribute(.underlineStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
            case .toggleStrikethrough:
                let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
                storage.addAttribute(.strikethroughStyle, value: current != 0 ? 0 : NSUnderlineStyle.single.rawValue, range: range)
            case .setFontSize(let size):
                let displaySize = size * renderScale
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    let font = (value as? UIFont) ?? textView.font ?? UIFont.systemFont(ofSize: displaySize)
                    storage.addAttribute(.font, value: UIFont(descriptor: font.fontDescriptor, size: displaySize), range: attrRange)
                }
            case .setColor(let color):
                storage.addAttribute(.foregroundColor, value: UIColor(color), range: range)
            case .clearFormatting:
                let plain = storage.string
                storage.setAttributedString(NSAttributedString(string: plain, attributes: textView.typingAttributes))
                shouldEncodeRichText = false
                pendingClearFormatting = true
            }
            storage.endEditing()
            // Only register undo and re-encode when the action actually changed the text.
            // SwiftUI's ColorPicker re-fires its binding with the already-applied color,
            // which would otherwise register a phantom no-op "undo nothing" step.
            if !storage.isEqual(to: prior) {
                registerFormattingUndo(restoring: prior, shouldEncode: priorShouldEncode, on: textView)
                textView.delegate?.textViewDidChange?(textView)
            }
        } else {
            shouldEncodeRichText = true
            textView.typingAttributes = updatedTypingAttributes(for: textView.typingAttributes, action: action)
            hasPendingTypingAttributes = true
        }

        refreshSelectionState()
    }

    /// Records an undo step on the text view's own manager that restores the whole
    /// attributed string `prior`, so undo reverts programmatic formatting (direct textStorage
    /// mutation otherwise registers nothing). `shouldEncode` is the pre-action encode flag, so
    /// undoing a clear (which sets it false) re-enables encoding — otherwise textViewDidChange
    /// would skip re-encoding and the restored formatting would be dropped on commit. The undo
    /// block snapshots the live state and re-registers itself, giving redo.
    private func registerFormattingUndo(restoring prior: NSAttributedString, shouldEncode: Bool, on textView: UITextView) {
        guard let undoManager = textView.undoManager else { return }
        undoManager.registerUndo(withTarget: textView) { [weak self] tv in
            let storage = tv.textStorage
            let redoPrior = NSAttributedString(attributedString: storage)
            let redoShouldEncode = self?.shouldEncodeRichText ?? false
            self?.registerFormattingUndo(restoring: redoPrior, shouldEncode: redoShouldEncode, on: tv)
            self?.shouldEncodeRichText = shouldEncode
            storage.beginEditing()
            storage.setAttributedString(prior)
            storage.endEditing()
            tv.delegate?.textViewDidChange?(tv)
        }
        undoManager.setActionName("Format Text")
    }

    private func updatedTypingAttributes(
        for attributes: [NSAttributedString.Key: Any],
        action: RichTextFormatAction
    ) -> [NSAttributedString.Key: Any] {
        var updated = attributes
        let baseFont = (updated[.font] as? UIFont) ?? textView?.font ?? UIFont.systemFont(ofSize: 14)

        switch action {
        case .toggleBold:
            updated[.font] = baseFont.toggling(.traitBold)
        case .toggleItalic:
            updated[.font] = baseFont.toggling(.traitItalic)
        case .toggleUnderline:
            let current = updated[.underlineStyle] as? Int ?? 0
            updated[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        case .toggleStrikethrough:
            let current = updated[.strikethroughStyle] as? Int ?? 0
            updated[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        case .setFontSize(let size):
            updated[.font] = UIFont(descriptor: baseFont.fontDescriptor, size: size * renderScale)
        case .setColor(let color):
            updated[.foregroundColor] = UIColor(color)
        case .clearFormatting:
            break
        }
        return updated
    }

    /// Single guarded write path for `selectionState` — avoids redundant SwiftUI invalidation of
    /// the accessory bar when the caret moves within identically-formatted text.
    func setSelectionState(_ newState: RichTextSelectionState) {
        if selectionState != newState { selectionState = newState }
    }

    private func refreshSelectionState() {
        guard let textView else { return }
        let range = textView.selectedRange
        let rawAttrs: [NSAttributedString.Key: Any]? = range.length > 0
            ? textView.textStorage.attributes(at: range.location, effectiveRange: nil)
            : textView.typingAttributes
        let attrs = modelScaledAttributes(rawAttrs, renderScale: renderScale)
        setSelectionState(RichTextSelectionState(from: attrs, hasRangeSelection: range.length > 0))
    }

    private func toggleFontTrait(_ trait: UIFontDescriptor.SymbolicTraits, range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            guard let font = value as? UIFont else { return }
            storage.addAttribute(.font, value: font.toggling(trait), range: attrRange)
        }
    }
}

/// Scales a selection's display-scale `.font` down to model space for the format bar / selection
/// state. Only the font carries scale; traits/underline/color are scale-independent.
private func modelScaledAttributes(
    _ attributes: [NSAttributedString.Key: Any]?,
    renderScale: CGFloat
) -> [NSAttributedString.Key: Any]? {
    guard renderScale != 1, renderScale > 0,
          var attrs = attributes, let font = attrs[.font] as? UIFont else { return attributes }
    attrs[.font] = font.withSize(font.pointSize / renderScale)
    return attrs
}

extension NSAttributedString {
    /// Returns a copy with all absolute font metrics (size, kerning, baseline offset, line
    /// spacing) multiplied by `scale`. Lets the iPad editor render at display scale — so selection
    /// handles are screen-sized — while the persisted rich text stays at model scale.
    func scaledFontMetrics(by scale: CGFloat) -> NSAttributedString {
        guard scale != 1, scale > 0, length > 0 else { return self }
        let result = NSMutableAttributedString(attributedString: self)
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attrs, range, _ in
            var updates: [NSAttributedString.Key: Any] = [:]
            if let font = attrs[.font] as? UIFont {
                updates[.font] = font.withSize(font.pointSize * scale)
            }
            if let kern = attrs[.kern] as? NSNumber {
                updates[.kern] = kern.doubleValue * scale
            }
            if let offset = attrs[.baselineOffset] as? NSNumber {
                updates[.baselineOffset] = offset.doubleValue * scale
            }
            if let style = attrs[.paragraphStyle] as? NSParagraphStyle,
               let mutable = style.mutableCopy() as? NSMutableParagraphStyle {
                mutable.lineSpacing *= scale
                mutable.minimumLineHeight *= scale
                mutable.maximumLineHeight *= scale
                updates[.paragraphStyle] = mutable
            }
            if !updates.isEmpty { result.addAttributes(updates, range: range) }
        }
        return result
    }
}
#endif
