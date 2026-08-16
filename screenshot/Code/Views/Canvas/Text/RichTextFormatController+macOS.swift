#if os(macOS)
import Combine
import SwiftUI

class RichTextFormatController: ObservableObject {
    private(set) var shouldEncodeRichText = false
    private(set) var hasPendingTypingAttributes = false
    var pendingClearFormatting = false
    weak var textView: NSTextView?
    weak var undoManager: UndoManager?

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
        guard let textView, let storage = textView.textStorage else { return }
        let range = textView.selectedRange()
        let priorShouldEncode = shouldEncodeRichText

        if range.length > 0 {
            let prior = NSAttributedString(attributedString: storage)
            shouldEncodeRichText = true
            storage.beginEditing()
            switch action {
            case .toggleBold:
                toggleFontTrait(.boldFontMask, range: range, storage: storage)
            case .toggleItalic:
                toggleFontTrait(.italicFontMask, range: range, storage: storage)
            case .toggleUnderline:
                let current = storage.attribute(.underlineStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
                let newValue: Int = current != 0 ? 0 : NSUnderlineStyle.single.rawValue
                storage.addAttribute(.underlineStyle, value: newValue, range: range)
            case .toggleStrikethrough:
                let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
                let newValue: Int = current != 0 ? 0 : NSUnderlineStyle.single.rawValue
                storage.addAttribute(.strikethroughStyle, value: newValue, range: range)
            case .setFontSize(let size):
                storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
                    let font = (value as? NSFont) ?? textView.font ?? NSFont.systemFont(ofSize: size)
                    let newFont = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
                    storage.addAttribute(.font, value: newFont, range: attrRange)
                }
            case .setColor(let color):
                storage.addAttribute(.foregroundColor, value: NSColor(color), range: range)
            case .clearFormatting:
                let plainText = storage.string
                storage.setAttributedString(NSAttributedString(string: plainText, attributes: textView.typingAttributes))
                shouldEncodeRichText = false
                pendingClearFormatting = true
            }
            storage.endEditing()

            if !storage.isEqual(to: prior) {
                registerFormattingUndo(restoring: prior, shouldEncode: priorShouldEncode, on: textView)
                textView.didChangeText()
            }
        } else {
            shouldEncodeRichText = true
            textView.typingAttributes = updatedTypingAttributes(for: textView.typingAttributes, action: action)
            textView.defaultParagraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            hasPendingTypingAttributes = true
        }

        NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: textView)
    }

    private func registerFormattingUndo(restoring prior: NSAttributedString, shouldEncode: Bool, on textView: NSTextView) {
        guard let undoManager = self.undoManager ?? textView.undoManager else { return }
        undoManager.registerUndo(withTarget: textView) { [weak self] tv in
            guard let storage = tv.textStorage else { return }
            let redoPrior = NSAttributedString(attributedString: storage)
            let redoShouldEncode = self?.shouldEncodeRichText ?? false
            self?.registerFormattingUndo(restoring: redoPrior, shouldEncode: redoShouldEncode, on: tv)
            self?.shouldEncodeRichText = shouldEncode
            storage.beginEditing()
            storage.setAttributedString(prior)
            storage.endEditing()
            tv.didChangeText()
        }
        undoManager.setActionName("Format Text")
    }

    private func updatedTypingAttributes(
        for attributes: [NSAttributedString.Key: Any],
        action: RichTextFormatAction
    ) -> [NSAttributedString.Key: Any] {
        var updated = attributes
        let baseFont = (updated[.font] as? NSFont) ?? textView?.font ?? NSFont.systemFont(ofSize: 14)

        switch action {
        case .toggleBold:
            updated[.font] = toggledFont(from: baseFont, trait: .boldFontMask)
        case .toggleItalic:
            updated[.font] = toggledFont(from: baseFont, trait: .italicFontMask)
        case .toggleUnderline:
            let current = updated[.underlineStyle] as? Int ?? 0
            updated[.underlineStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        case .toggleStrikethrough:
            let current = updated[.strikethroughStyle] as? Int ?? 0
            updated[.strikethroughStyle] = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        case .setFontSize(let size):
            updated[.font] = NSFont(descriptor: baseFont.fontDescriptor, size: size) ?? baseFont
        case .setColor(let color):
            updated[.foregroundColor] = NSColor(color)
        case .clearFormatting:
            break
        }

        return updated
    }

    private func toggleFontTrait(_ trait: NSFontTraitMask, range: NSRange, storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: toggledFont(from: font, trait: trait), range: attrRange)
        }
    }

    private func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let fm = NSFontManager.shared
        let hasTrait = font.fontDescriptor.symbolicTraits.contains(
            trait == .boldFontMask ? .bold : .italic
        )
        if hasTrait {
            return fm.convert(font, toNotHaveTrait: trait)
        }
        return fm.convert(font, toHaveTrait: trait)
    }
}
#endif
