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

    @Test func customFontRegistryKeepsExactFaceForStyleQualifiedSelection() {
        CustomFontRegistry.update(with: [
            "Family-Bold.otf": CustomFont(
                fileName: "Family-Bold.otf",
                familyName: "Family",
                styleName: "Bold",
                postScriptName: "Family-Bold",
                isBold: true,
                isItalic: false
            )
        ])
        defer { CustomFontRegistry.update(with: [:]) }

        let resolved = CustomFontRegistry.resolve("Family Bold")
        #expect(resolved.family == "Family")
        #expect(resolved.exactName == "Family-Bold")
        #expect(resolved.italic == false)
    }

    @Test func preferredSelectionPrefersRegularVariantWhenAvailable() {
        let fonts: [String: CustomFont] = [
            "Family-Regular.otf": CustomFont(
                fileName: "Family-Regular.otf",
                familyName: "Family",
                styleName: "Regular",
                postScriptName: "Family-Regular",
                isBold: false,
                isItalic: false
            ),
            "Family-Italic.otf": CustomFont(
                fileName: "Family-Italic.otf",
                familyName: "Family",
                styleName: "Italic",
                postScriptName: "Family-Italic",
                isBold: false,
                isItalic: true
            ),
            "Family-Bold.otf": CustomFont(
                fileName: "Family-Bold.otf",
                familyName: "Family",
                styleName: "Bold",
                postScriptName: "Family-Bold",
                isBold: true,
                isItalic: false
            )
        ]

        let selection = CustomFontRegistry.preferredSelection(for: "Family", in: fonts)
        #expect(selection?.fontName == "Family Regular")
        #expect(selection?.fontWeight == 400)
        #expect(selection?.italic == false)
    }

    @Test func selectionResultKeepsExactVariantTraits() {
        let boldItalic = CustomFont(
            fileName: "Family-BoldItalic.otf",
            familyName: "Family",
            styleName: "Bold Italic",
            postScriptName: "Family-BoldItalic",
            isBold: true,
            isItalic: true
        )

        let selection = boldItalic.selectionResult()
        #expect(selection.fontName == "Family Bold Italic")
        #expect(selection.fontWeight == 700)
        #expect(selection.italic == true)
    }

    @Test func displayNameIncludesRegularStyleForTransparency() {
        let regular = CustomFont(
            fileName: "Family-Regular.otf",
            familyName: "Family",
            styleName: "Regular",
            postScriptName: "Family-Regular",
            isBold: false,
            isItalic: false
        )

        #expect(regular.displayName == "Family Regular")
    }

    @Test func controlStateShowsOnlySwitchableWeightsForExactVariant() {
        let regular = CustomFont(
            fileName: "Family-Regular.otf",
            familyName: "Family",
            styleName: "Regular",
            postScriptName: "Family-Regular",
            isBold: false,
            isItalic: false
        )
        let bold = CustomFont(
            fileName: "Family-Bold.otf",
            familyName: "Family",
            styleName: "Bold",
            postScriptName: "Family-Bold",
            isBold: true,
            isItalic: false
        )
        let italic = CustomFont(
            fileName: "Family-Italic.otf",
            familyName: "Family",
            styleName: "Italic",
            postScriptName: "Family-Italic",
            isBold: false,
            isItalic: true
        )

        CustomFontRegistry.update(with: [
            regular.fileName: regular,
            bold.fileName: bold,
            italic.fileName: italic
        ])
        defer { CustomFontRegistry.update(with: [:]) }

        let state = CustomFontRegistry.controlState(name: "Family Regular", fontWeight: nil, italic: nil)
        #expect(state?.effectiveItalic == false)
        #expect(state?.effectiveWeight == 400)
        #expect(state?.availableWeights == [400, 700])
        #expect(state?.showsWeightPicker == true)
        #expect(state?.showsItalicToggle == true)
    }

    @Test func selectionSwitchesToMatchingExactVariant() {
        let bold = CustomFont(
            fileName: "Family-Bold.otf",
            familyName: "Family",
            styleName: "Bold",
            postScriptName: "Family-Bold",
            isBold: true,
            isItalic: false
        )
        let boldItalic = CustomFont(
            fileName: "Family-BoldItalic.otf",
            familyName: "Family",
            styleName: "Bold Italic",
            postScriptName: "Family-BoldItalic",
            isBold: true,
            isItalic: true
        )

        CustomFontRegistry.update(with: [
            bold.fileName: bold,
            boldItalic.fileName: boldItalic
        ])
        defer { CustomFontRegistry.update(with: [:]) }

        let selection = CustomFontRegistry.selection(
            name: "Family Bold",
            fontWeight: 700,
            italic: true
        )

        #expect(selection?.fontName == "Family Bold Italic")
        #expect(selection?.fontWeight == 700)
        #expect(selection?.italic == true)
    }

    @Test func controlStateHidesUnsupportedControlsForSingleVariant() {
        let italic = CustomFont(
            fileName: "Family-Italic.otf",
            familyName: "Family",
            styleName: "Italic",
            postScriptName: "Family-Italic",
            isBold: false,
            isItalic: true
        )

        CustomFontRegistry.update(with: [italic.fileName: italic])
        defer { CustomFontRegistry.update(with: [:]) }

        let state = CustomFontRegistry.controlState(name: "Family Italic", fontWeight: nil, italic: nil)
        #expect(state?.effectiveItalic == true)
        #expect(state?.availableWeights == [400])
        #expect(state?.showsWeightPicker == false)
        #expect(state?.showsItalicToggle == false)
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
