import CoreGraphics
import Testing
import AppKit
import SwiftUI
@testable import Screenshot_Bro

@Suite(.serialized)
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

    @Test func temporaryCustomFontRegistryRestoresActiveProjectFonts() {
        let active = CustomFont(
            fileName: "Active.otf",
            familyName: "Active Family",
            styleName: "Regular",
            postScriptName: "Active-Regular",
            isBold: false,
            isItalic: false
        )
        let thumbnail = CustomFont(
            fileName: "Thumbnail.otf",
            familyName: "Thumbnail Family",
            styleName: "Regular",
            postScriptName: "Thumbnail-Regular",
            isBold: false,
            isItalic: false
        )
        CustomFontRegistry.update(with: [active.fileName: active], instances: [active])
        defer { CustomFontRegistry.update(with: [:]) }

        CustomFontRegistry.withTemporaryFonts(
            [thumbnail.fileName: thumbnail],
            instances: [thumbnail]
        ) {
            #expect(CustomFontRegistry.resolve("Thumbnail Family Regular").exactName == "Thumbnail-Regular")
            #expect(CustomFontRegistry.postScriptName(
                forFamily: "Active Family",
                managerWeight: 5,
                italic: false
            ) == nil)
        }

        #expect(CustomFontRegistry.resolve("Active Family Regular").exactName == "Active-Regular")
        #expect(CustomFontRegistry.postScriptName(
            forFamily: "Active Family",
            managerWeight: 5,
            italic: false
        ) == "Active-Regular")
    }

    @Test func postScriptNameResolvesBareFamilyToWeightSpecificInstance() {
        // A variable font exposes one CustomFont per named instance; the picker/byFamily keep a
        // single primary face, but the instance table must hold every weight so a bare family
        // name (as templates store, e.g. "DM Sans") resolves to the exact PostScript name. iOS
        // renders process-registered fonts only by PostScript name — family resolution yields
        // the "????" tofu this guards against.
        func variant(_ style: String, _ ps: String) -> CustomFont {
            CustomFont(fileName: "DMSans.ttf", familyName: "DM Sans", styleName: style,
                       postScriptName: ps, isBold: style.contains("Bold"), isItalic: false)
        }
        let instances = [
            variant("Regular", "DMSans-Regular"),
            variant("Medium", "DMSans-Medium"),
            variant("SemiBold", "DMSans-SemiBold"),
            variant("Bold", "DMSans-Bold"),
        ]
        CustomFontRegistry.update(with: [instances[0].fileName: instances[0]], instances: instances)
        defer { CustomFontRegistry.update(with: [:]) }

        // managerWeight: regular=5, medium=6, semibold=8, bold=9 (NSFontManager scale).
        #expect(CustomFontRegistry.postScriptName(forFamily: "DM Sans", managerWeight: 5, italic: false) == "DMSans-Regular")
        #expect(CustomFontRegistry.postScriptName(forFamily: "DM Sans", managerWeight: 6, italic: false) == "DMSans-Medium")
        #expect(CustomFontRegistry.postScriptName(forFamily: "DM Sans", managerWeight: 8, italic: false) == "DMSans-SemiBold")
        #expect(CustomFontRegistry.postScriptName(forFamily: "DM Sans", managerWeight: 9, italic: false) == "DMSans-Bold")
        #expect(CustomFontRegistry.postScriptName(forFamily: "Unknown", managerWeight: 5, italic: false) == nil)
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

    /// iPad rich-text editing persists per-range formatting through the same Base64-RTF path.
    /// Guards that distinct bold/color runs survive an encode→decode round-trip intact.
    @Test func mixedFormattingRunsSurviveRoundTrip() throws {
        let attributed = NSMutableAttributedString(string: "Hello world")
        let boldRed: [NSAttributedString.Key: Any] = [
            .font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 24), toHaveTrait: .boldFontMask),
            .foregroundColor: NSColor.systemRed
        ]
        let plain: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ]
        attributed.setAttributes(boldRed, range: NSRange(location: 0, length: 5))   // "Hello"
        attributed.setAttributes(plain, range: NSRange(location: 5, length: 6))      // " world"

        let encoded = try #require(RichTextUtils.encode(attributed))
        let decoded = try #require(RichTextUtils.decode(encoded))

        #expect(decoded.string == "Hello world")

        let firstFont = decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let lastFont = decoded.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
        #expect(firstFont?.hasBoldTrait == true)
        #expect(lastFont?.hasBoldTrait == false)

        let firstColor = rgbaComponents(decoded.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let expectedRed = rgbaComponents(.systemRed)
        #expect(firstColor != nil)
        #expect(abs((firstColor?.0 ?? 0) - (expectedRed?.0 ?? 0)) < 0.05)
        #expect(abs((firstColor?.1 ?? 0) - (expectedRed?.1 ?? 0)) < 0.05)
        #expect(abs((firstColor?.2 ?? 0) - (expectedRed?.2 ?? 0)) < 0.05)
    }

    private func distinctPointSizes(_ string: NSAttributedString) -> Set<CGFloat> {
        var sizes = Set<CGFloat>()
        string.enumerateAttribute(.font, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let font = value as? NSFont { sizes.insert(font.pointSize) }
        }
        return sizes
    }

    private func mixedSizeShape() -> CanvasShapeModel {
        // "Hello " at 72pt, "world" at 120pt — the default system font, mirroring what the
        // floating format bar produces when a word is given a different size.
        let attributed = NSMutableAttributedString(string: "Hello world")
        attributed.setAttributes(
            [.font: NSFont.systemFont(ofSize: 72), .foregroundColor: NSColor.white],
            range: NSRange(location: 0, length: 6)
        )
        attributed.setAttributes(
            [.font: NSFont.systemFont(ofSize: 120), .foregroundColor: NSColor.white],
            range: NSRange(location: 6, length: 5)
        )
        var shape = CanvasShapeModel(type: .text, text: "Hello world", fontSize: 72)
        shape.richText = RichTextUtils.encode(attributed)
        return shape
    }

    /// `syncShapeStyle(.fontSize)` intentionally flattens mixed per-run sizes to the shape's single
    /// `fontSize`. This is why callers must NOT invoke it for a no-op size change — the properties-bar
    /// font-size field guards on `resolved.fontSize != newSize` so a stray re-render (which reprograms
    /// the field to the current value) can't silently collapse an enlarged word.
    @Test func fontSizeSyncFlattensMixedRunSizes() throws {
        var shape = mixedSizeShape()          // runs at 72 and 120, shape.fontSize == 72
        RichTextUtils.syncShapeStyle(in: &shape, property: .fontSize)
        let decoded = try #require(RichTextUtils.decode(shape.richText ?? ""))
        #expect(distinctPointSizes(decoded) == [72])
    }

    /// Repro (hypothesis 2): re-applying the font family must not flatten per-run sizes in the
    /// stored rich text.
    @Test func fontNameSyncPreservesMixedRunSizes() throws {
        var shape = mixedSizeShape()
        #expect(distinctPointSizes(try #require(RichTextUtils.decode(shape.richText ?? ""))) == [72, 120])

        RichTextUtils.syncShapeStyle(in: &shape, property: .fontName)

        let decoded = try #require(RichTextUtils.decode(shape.richText ?? ""))
        #expect(decoded.string == "Hello world")
        #expect(distinctPointSizes(decoded) == [72, 120])
    }

    /// Repro (hypothesis 1): after the font-name re-encode, the render path (`buildAttributedString`
    /// with `plainText == shape.text`) must still show two distinct sizes — i.e. the stale-text
    /// `retargetAttributedString` fallback must NOT fire and collapse every run to the first.
    @Test func fontNameSyncThenBuildKeepsMixedSizes() throws {
        var shape = mixedSizeShape()
        RichTextUtils.syncShapeStyle(in: &shape, property: .fontName)

        let rebuilt = RichTextUtils.buildAttributedString(
            richText: shape.richText,
            plainText: shape.text ?? "",
            font: NSFont.systemFont(ofSize: 72),
            color: .white,
            alignment: .center,
            letterSpacing: nil,
            lineHeightMultiple: nil,
            legacyLineSpacing: nil,
            uppercase: false
        )

        #expect(rebuilt.string == "Hello world")
        #expect(distinctPointSizes(rebuilt) == [72, 120])
    }

    /// Directly exposes any string drift introduced by the font-name re-encode: the decoded
    /// rich-text string must keep matching `shape.text`, or the render's equality guard trips.
    @Test func fontNameSyncKeepsRichTextStringMatchingPlainText() throws {
        var shape = mixedSizeShape()
        RichTextUtils.syncShapeStyle(in: &shape, property: .fontName)

        let decoded = try #require(RichTextUtils.decode(shape.richText ?? ""))
        #expect(decoded.string == (shape.text ?? ""))
    }

    /// Repro of the reported bug: a MULTI-LINE label with one enlarged word. When the edit commits
    /// and the canvas re-renders through `buildAttributedString`, mixed per-run sizes must survive —
    /// the newline must not trip the stale-text `retargetAttributedString` fallback that flattens runs.
    @Test func multilineMixedSizesSurviveDisplayBuild() throws {
        let text = "Light up\nyour workflow"
        let attributed = NSMutableAttributedString(string: text)
        let splitIndex = (text as NSString).range(of: "your").location
        attributed.setAttributes(
            [.font: NSFont.systemFont(ofSize: 108, weight: .bold), .foregroundColor: NSColor.white],
            range: NSRange(location: 0, length: splitIndex)
        )
        attributed.setAttributes(
            [.font: NSFont.systemFont(ofSize: 192, weight: .bold), .foregroundColor: NSColor.white],
            range: NSRange(location: splitIndex, length: (text as NSString).length - splitIndex)
        )
        let encoded = try #require(RichTextUtils.encode(attributed))

        let decoded = try #require(RichTextUtils.decode(encoded))
        #expect(decoded.string == text)

        let rebuilt = RichTextUtils.buildAttributedString(
            richText: encoded,
            plainText: text,
            font: NSFont.systemFont(ofSize: 108, weight: .bold),
            color: .white,
            alignment: .center,
            letterSpacing: nil,
            lineHeightMultiple: nil,
            legacyLineSpacing: nil,
            uppercase: false
        )
        #expect(rebuilt.string == text)
        #expect(distinctPointSizes(rebuilt) == [108, 192])
    }

    /// Mirrors the *real* creation path: a uniform build from the shape font (bold system default),
    /// then the format controller's `NSFont(descriptor:size:)` applied to one word — then a
    /// font-name re-apply. This is the path the user actually exercises.
    @Test func formatBarSizeChangeSurvivesFontNameReapply() throws {
        let baseFont = NSFont.systemFont(ofSize: 72, weight: .bold)
        let initial = RichTextUtils.buildAttributedString(
            richText: nil,
            plainText: "Hello world",
            font: baseFont,
            color: .white,
            alignment: .center,
            letterSpacing: nil,
            lineHeightMultiple: nil,
            legacyLineSpacing: nil,
            uppercase: false
        )
        let storage = NSMutableAttributedString(attributedString: initial)
        let range = NSRange(location: 6, length: 5) // "world"
        storage.enumerateAttribute(.font, in: range) { value, attrRange, _ in
            let font = (value as? NSFont) ?? baseFont
            let newFont = NSFont(descriptor: font.fontDescriptor, size: 120) ?? font
            storage.addAttribute(.font, value: newFont, range: attrRange)
        }

        var shape = CanvasShapeModel(type: .text, text: "Hello world", fontSize: 72)
        shape.fontWeight = 700
        shape.richText = RichTextUtils.encode(storage)
        #expect(distinctPointSizes(try #require(RichTextUtils.decode(shape.richText ?? ""))) == [72, 120])

        RichTextUtils.syncShapeStyle(in: &shape, property: .fontName)

        let decoded = try #require(RichTextUtils.decode(shape.richText ?? ""))
        #expect(decoded.string == "Hello world")
        #expect(distinctPointSizes(decoded) == [72, 120])
    }
}
