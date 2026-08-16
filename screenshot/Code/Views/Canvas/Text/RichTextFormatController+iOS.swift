#if os(iOS)
import Combine
import SwiftUI
import UIKit

final class RichTextFormatController: ObservableObject {
    private(set) var shouldEncodeRichText = false
    private(set) var hasPendingTypingAttributes = false
    var pendingClearFormatting = false
    weak var textView: UITextView?
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

func modelScaledAttributes(
    _ attributes: [NSAttributedString.Key: Any]?,
    renderScale: CGFloat
) -> [NSAttributedString.Key: Any]? {
    guard renderScale != 1, renderScale > 0,
          var attrs = attributes, let font = attrs[.font] as? UIFont else { return attributes }
    attrs[.font] = font.withSize(font.pointSize / renderScale)
    return attrs
}

extension NSAttributedString {
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
