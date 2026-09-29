#if os(macOS)
import AppKit

final class TextLayoutNSView: NSView {
    private let textStorage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private let compactDelegate = CompactLineLayoutDelegate()
    private var verticalAlignment: TextVerticalAlign = .center
    private var verticalGlyphPadding: CGFloat = 0

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
    private var lastFontScale: CGFloat?
    private var lastGlyphFill: TextGlyphFill?
    private var stroke: TextStroke?

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
        richTextData: String? = nil,
        fontScale: CGFloat = 1,
        stroke: TextStroke? = nil,
        glyphFill: TextGlyphFill? = nil
    ) {
        if stroke != self.stroke {
            self.stroke = stroke
            needsLayout = true
            needsDisplay = true
        }
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
            || fontScale != lastFontScale
            || glyphFill != lastGlyphFill
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
        lastFontScale = fontScale
        lastGlyphFill = glyphFill

        self.verticalAlignment = verticalAlignment
        compactDelegate.lineHeightMultiple = lineHeightMultiple ?? 1.0
        self.verticalGlyphPadding = TextLayoutStyle.verticalGlyphPadding(
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            font: fontScale == 1 ? font : font.withSize(font.pointSize * fontScale)
        )

        textStorage.setAttributedString(TextLayoutStyle.overridingForeground(RichTextUtils.buildAttributedString(
            richText: richTextData,
            plainText: text,
            font: font,
            color: color,
            alignment: alignment,
            letterSpacing: letterSpacing,
            lineHeightMultiple: lineHeightMultiple,
            legacyLineSpacing: legacyLineSpacing,
            uppercase: uppercase,
            fontScale: fontScale
        ), with: glyphFill))
        needsDisplay = true
    }

    /// Room around the text box for an outline, which the raster otherwise clips at the box edge.
    private var contentInset: CGFloat { stroke?.rasterPadding ?? 0 }

    override func layout() {
        super.layout()
        textContainer.size = bounds.insetBy(dx: contentInset, dy: contentInset).size
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let yOffset = TextLayoutStyle.verticalOffset(
            containerHeight: bounds.height - 2 * contentInset,
            contentHeight: usedRect.height,
            padding: verticalGlyphPadding,
            alignment: verticalAlignment
        )

        let origin = NSPoint(x: contentInset, y: contentInset + yOffset)
        layoutManager.drawBackground(forGlyphRange: glyphRange, at: origin)
        if let stroke {
            TextLayoutStyle.applyStroke(to: textStorage, color: stroke.color, width: stroke.width)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
            TextLayoutStyle.removeStroke(from: textStorage)
        }
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
    }
}
#endif
