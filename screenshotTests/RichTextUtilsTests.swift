import Testing
import AppKit
import SwiftUI
@testable import Screenshot_Bro

struct RichTextUtilsTests {

    private func rgbaComponents(_ color: NSColor?) -> (CGFloat, CGFloat, CGFloat, CGFloat)? {
        guard let converted = color?.usingColorSpace(.sRGB) else { return nil }
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }

    @Test func syncShapeStyleUpdatesGlobalColor() {
        let attributed = NSMutableAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.systemBlue
        ])
        var shape = CanvasShapeModel(type: .text, text: "Hello")
        shape.color = .red
        shape.richText = RichTextUtils.encode(attributed)

        RichTextUtils.syncShapeStyle(in: &shape, property: .color)

        let decoded = RichTextUtils.decode(shape.richText ?? "")
        let color = decoded?.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let actual = rgbaComponents(color)
        let expected = rgbaComponents(NSColor(shape.color))
        #expect(actual != nil)
        #expect(expected != nil)
        #expect(abs((actual?.0 ?? 0) - (expected?.0 ?? 0)) < 0.05)
        #expect(abs((actual?.1 ?? 0) - (expected?.1 ?? 0)) < 0.05)
        #expect(abs((actual?.2 ?? 0) - (expected?.2 ?? 0)) < 0.05)
        #expect(abs((actual?.3 ?? 0) - (expected?.3 ?? 0)) < 0.05)
    }

    @Test func syncShapeStyleUpdatesFontSizeWithoutDroppingBoldTrait() {
        let boldFont = NSFontManager.shared.convert(
            NSFont.systemFont(ofSize: 24, weight: .regular),
            toHaveTrait: .boldFontMask
        )
        let attributed = NSMutableAttributedString(string: "Hello", attributes: [
            .font: boldFont
        ])
        var shape = CanvasShapeModel(type: .text, text: "Hello", fontSize: 40)
        shape.richText = RichTextUtils.encode(attributed)

        RichTextUtils.syncShapeStyle(in: &shape, property: .fontSize)

        let decoded = RichTextUtils.decode(shape.richText ?? "")
        let font = decoded?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 40)
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func buildAttributedStringMergesUpdatedParagraphStyleIntoRichText() {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        let attributed = NSMutableAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .paragraphStyle: paragraph
        ])
        let encoded = RichTextUtils.encode(attributed)

        let rebuilt = RichTextUtils.buildAttributedString(
            richText: encoded,
            plainText: "Hello",
            font: NSFont.systemFont(ofSize: 24, weight: .regular),
            color: .white,
            alignment: .right,
            letterSpacing: 2,
            lineHeightMultiple: 1.3,
            legacyLineSpacing: nil,
            uppercase: false
        )

        let mergedParagraph = rebuilt.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        let kern = rebuilt.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat
        #expect(mergedParagraph?.alignment == .right)
        #expect(kern == 2)
    }

    @Test func buildAttributedStringUsesPlainTextWhenStoredRichTextIsStale() {
        let attributed = NSMutableAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 24, weight: .regular),
            .foregroundColor: NSColor.systemBlue
        ])
        let encoded = RichTextUtils.encode(attributed)

        let rebuilt = RichTextUtils.buildAttributedString(
            richText: encoded,
            plainText: "Bonjour",
            font: NSFont.systemFont(ofSize: 24, weight: .regular),
            color: .white,
            alignment: .center,
            letterSpacing: nil,
            lineHeightMultiple: nil,
            legacyLineSpacing: nil,
            uppercase: false
        )

        #expect(rebuilt.string == "Bonjour")
        let color = rebuilt.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let actual = rgbaComponents(color)
        let expected = rgbaComponents(.systemBlue)
        #expect(actual != nil)
        #expect(expected != nil)
        #expect(abs((actual?.0 ?? 0) - (expected?.0 ?? 0)) < 0.05)
        #expect(abs((actual?.1 ?? 0) - (expected?.1 ?? 0)) < 0.05)
        #expect(abs((actual?.2 ?? 0) - (expected?.2 ?? 0)) < 0.05)
    }
}
