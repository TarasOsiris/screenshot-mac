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
            legacyLineSpacing: legacyLineSpacing
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
            legacyLineSpacing: legacyLineSpacing
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
                legacyLineSpacing: legacyLineSpacing
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

        DispatchQueue.main.async {
            scrollView.centerDocumentView()
            textView.window?.makeFirstResponder(textView)
            textView.selectAll(nil)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: CenteringScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyTextStyle(to: textView)
        if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
        scrollView.verticalAlignment = verticalAlignment
        scrollView.centerDocumentView()
    }

    private func applyTextStyle(to textView: NSTextView, preserveSelection: Bool = true) {
        if let delegate = textView.layoutManager?.delegate as? CompactLineLayoutDelegate {
            delegate.lineHeightMultiple = lineHeightMultiple ?? TextLayoutStyle.defaultLineHeightMultiple
        }
        let displayText = uppercase ? text.uppercased() : text
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
            storage.setAttributedString(NSAttributedString(string: displayText, attributes: attributes))
        } else {
            textView.string = displayText
        }

        textView.font = font
        textView.textColor = color
        textView.alignment = alignment
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
            // typingAttributes ensure the next keystroke uses correct style;
            // full restyling happens in updateNSView triggered by the binding change above.
            textView.typingAttributes = TextLayoutStyle.textAttributes(
                font: parent.font,
                color: parent.color,
                alignment: parent.alignment,
                letterSpacing: parent.letterSpacing,
                includeBaselineOffset: false,
                lineHeightMultiple: parent.lineHeightMultiple,
                legacyLineSpacing: parent.legacyLineSpacing
            )
            if let scrollView = textView.enclosingScrollView as? CenteringScrollView {
                if let tc = textView.textContainer { textView.layoutManager?.ensureLayout(for: tc) }
                scrollView.centerDocumentView()
            }
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
        legacyLineSpacing: CGFloat?
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

        self.verticalAlignment = verticalAlignment
        compactDelegate.lineHeightMultiple = lineHeightMultiple ?? 1.0
        self.verticalGlyphPadding = TextLayoutStyle.verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: font
        )
        let displayText = uppercase ? text.uppercased() : text
        let attributedText = NSAttributedString(
            string: displayText,
            attributes: TextLayoutStyle.textAttributes(
                font: font,
                color: color,
                alignment: alignment,
                letterSpacing: letterSpacing,
                lineHeightMultiple: lineHeightMultiple,
                legacyLineSpacing: legacyLineSpacing
            )
        )
        textStorage.setAttributedString(attributedText)
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
