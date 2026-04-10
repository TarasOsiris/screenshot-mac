import Combine
import SwiftUI

struct LiveDisplayTextView: NSViewRepresentable {
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

    func makeNSView(context: Context) -> TextLayoutNSView {
        let view = TextLayoutNSView(frame: .zero)
        view.configure(
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
        return view
    }

    func updateNSView(_ view: TextLayoutNSView, context: Context) {
        view.configure(
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

struct RasterizedDisplayTextView: View {
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
        GeometryReader { proxy in
            if let image = TextLayoutStyle.renderImage(
                size: proxy.size,
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
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            } else {
                Color.clear
            }
        }
    }
}

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

        DispatchQueue.main.async {
            scrollView.centerDocumentView()
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: CenteringScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        formatController?.textView = textView

        // In rich text mode, don't rebuild the attributed string on every update
        // to avoid destroying per-range formatting during editing.
        let shouldPreserveRichTextStorage = isRichTextMode
            && (
                context.coordinator.hasPendingRichTextEdit(matching: richTextData)
                || formatController?.hasPendingTypingAttributes == true
            )

        if shouldPreserveRichTextStorage {
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
            storage.setAttributedString(RichTextUtils.buildAttributedString(
                richText: richTextData,
                plainText: text,
                font: font,
                color: color,
                alignment: alignment,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing,
                uppercase: uppercase
            ))
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
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0 {
                let attrs = textView.textStorage?.attributes(at: selectedRange.location, effectiveRange: nil)
                parent.onSelectionChange?(attrs, selectedRange)
            } else {
                parent.onSelectionChange?(textView.typingAttributes, nil)
            }
        }

        func hasPendingRichTextEdit(matching richTextData: String?) -> Bool {
            hasReceivedTextChange && richTextData == lastEmittedRichTextData
        }
    }
}

final class TextLayoutNSView: NSView {
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private let compactDelegate = CompactLineLayoutDelegate()
    private var verticalAlignment: TextVerticalAlign = .center
    private var verticalGlyphPadding: CGFloat = 0

    // Change-detection state to skip redundant configure() calls
    private var lastText: String?
    private var lastFont: NSFont?
    private var lastColor: NSColor?
    private var lastAlignment: NSTextAlignment?
    private var lastVerticalAlignment: TextVerticalAlign?
    private var lastUppercase: Bool?
    private var lastLetterSpacing: CGFloat?
    private var lastLineHeightMultiple: CGFloat?
    private var lastLegacyLineSpacing: CGFloat?
    private var lastRichTextData: String?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        textContainer.lineFragmentPadding = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        layoutManager.delegate = compactDelegate
        textStorage.addLayoutManager(layoutManager)
    }

    func configure(
        text: String,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment,
        verticalAlignment: TextVerticalAlign,
        uppercase: Bool,
        letterSpacing: CGFloat?,
        lineHeightMultiple: CGFloat?,
        legacyLineSpacing: CGFloat?,
        richTextData: String? = nil
    ) {
        guard text != lastText
            || font != lastFont
            || color != lastColor
            || alignment != lastAlignment
            || verticalAlignment != lastVerticalAlignment
            || uppercase != lastUppercase
            || letterSpacing != lastLetterSpacing
            || lineHeightMultiple != lastLineHeightMultiple
            || legacyLineSpacing != lastLegacyLineSpacing
            || richTextData != lastRichTextData
        else { return }

        lastText = text
        lastFont = font
        lastColor = color
        lastAlignment = alignment
        lastVerticalAlignment = verticalAlignment
        lastUppercase = uppercase
        lastLetterSpacing = letterSpacing
        lastLineHeightMultiple = lineHeightMultiple
        lastLegacyLineSpacing = legacyLineSpacing
        lastRichTextData = richTextData

        self.verticalAlignment = verticalAlignment
        compactDelegate.lineHeightMultiple = lineHeightMultiple ?? 1.0
        self.verticalGlyphPadding = TextLayoutStyle.verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )

        textStorage.setAttributedString(RichTextUtils.buildAttributedString(
            richText: richTextData,
            plainText: text,
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            uppercase: uppercase
        ))
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        textContainer.size = bounds.size
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let paddedTextHeight = usedRect.height + (verticalGlyphPadding * 2)

        let yOffset: CGFloat = switch verticalAlignment {
        case .top:
            verticalGlyphPadding
        case .center:
            max(0, (bounds.height - paddedTextHeight) / 2) + verticalGlyphPadding
        case .bottom:
            max(0, bounds.height - paddedTextHeight) + verticalGlyphPadding
        }

        let origin = NSPoint(x: 0, y: yOffset)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}

class CenteringScrollView: NSScrollView {
    weak var centerTextView: NSTextView?
    var verticalAlignment: TextVerticalAlign = .center

    func centerDocumentView() {
        guard let textView = centerTextView else { return }
        guard let tc = textView.textContainer else { return }
        let glyphPadding = (textView as? CommitTextView)?.verticalGlyphPadding ?? 0
        let textHeight = textView.layoutManager?.usedRect(for: tc).height ?? 0
        let paddedTextHeight = textHeight + glyphPadding
        let viewHeight = contentSize.height
        let targetHeight = max(viewHeight, paddedTextHeight)
        let targetSize = NSSize(width: contentSize.width, height: targetHeight)
        if textView.frame.size != targetSize {
            textView.setFrameSize(targetSize)
        }
        if paddedTextHeight < viewHeight {
            let topInset: CGFloat
            switch verticalAlignment {
            case .top:
                topInset = glyphPadding
            case .center:
                topInset = glyphPadding + ((viewHeight - paddedTextHeight) / 2)
            case .bottom:
                topInset = glyphPadding + (viewHeight - paddedTextHeight)
            }
            textView.textContainerInset = NSSize(width: 0, height: topInset)
        } else {
            textView.textContainerInset = NSSize(width: 0, height: glyphPadding)
        }
    }

    override func layout() {
        super.layout()
        centerDocumentView()
    }
}

private class CommitTextView: NSTextView {
    var onCommit: (() -> Void)?
    var verticalGlyphPadding: CGFloat = 0

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && event.modifierFlags.contains(.shift) {
            // Shift+Return -> commit
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

/// Controller for applying rich text format actions to an active NSTextView from outside (e.g., floating toolbar).
class RichTextFormatController: ObservableObject {
    private(set) var shouldEncodeRichText = false
    private(set) var hasPendingTypingAttributes = false
    var pendingClearFormatting = false
    weak var textView: NSTextView?

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
        shouldEncodeRichText = true

        if range.length > 0 {
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

            textView.didChangeText()
        } else {
            textView.typingAttributes = updatedTypingAttributes(for: textView.typingAttributes, action: action)
            textView.defaultParagraphStyle = textView.typingAttributes[.paragraphStyle] as? NSParagraphStyle
            hasPendingTypingAttributes = true
        }

        NotificationCenter.default.post(name: NSTextView.didChangeSelectionNotification, object: textView)
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
