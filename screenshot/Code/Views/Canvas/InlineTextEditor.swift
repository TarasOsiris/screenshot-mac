import Combine
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(macOS)
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
#else
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
#endif

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

#if os(macOS)
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
        // Clear the (weak) format-controller back-reference if it still points
        // at the text view being torn down.
        if let textView = scrollView.documentView as? NSTextView,
           coordinator.parent.formatController?.textView === textView {
            coordinator.parent.formatController?.textView = nil
        }
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
        let yOffset = TextLayoutStyle.verticalOffset(
            containerHeight: bounds.height,
            contentHeight: usedRect.height,
            padding: verticalGlyphPadding,
            alignment: verticalAlignment
        )

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
    weak var formatController: RichTextFormatController?

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
        // Cmd+B / Cmd+I / Cmd+U -> toggle formatting on the current selection
        // (only the bare Cmd chord — ignore Cmd+Shift+B etc. so other shortcuts pass through)
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
#else

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
        shouldEncodeRichText = true

        if range.length > 0 {
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
            textView.delegate?.textViewDidChange?(textView)
        } else {
            textView.typingAttributes = updatedTypingAttributes(for: textView.typingAttributes, action: action)
            hasPendingTypingAttributes = true
        }

        refreshSelectionState()
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
