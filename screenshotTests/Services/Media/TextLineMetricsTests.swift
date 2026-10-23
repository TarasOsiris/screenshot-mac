import CoreText
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// DM Sans has no Cyrillic, so Cyrillic text in it falls back per glyph while spaces stay in DM Sans.
@MainActor
struct TextLineMetricsTests {
    private static let cyrillic = "Записуй тренування за секунди"

    private func latinOnlyFont(size: CGFloat) throws -> NSFont {
        let fontsURL = try #require(TemplateService.sharedFontsURL)
        let url = fontsURL.appendingPathComponent("DMSans-VariableFont_opsz,wght.ttf")
        let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])
        let font = CTFontCreateWithFontDescriptor(try #require(descriptors.first), size, nil)
        var cyrillicChar = Array("З".utf16)
        var glyph = [CGGlyph](repeating: 0, count: 1)
        #expect(!CTFontGetGlyphsForCharacters(font, &cyrillicChar, &glyph, 1), "fixture must lack Cyrillic")
        return font as NSFont
    }

    private func lineHeights(_ attributed: NSAttributedString, width: CGFloat, multiple: CGFloat? = nil) -> [CGFloat] {
        let stack = TextLayoutStack(containerSize: CGSize(width: width, height: 10_000), lineHeightMultiple: multiple)
        stack.storage.setAttributedString(attributed)
        return lineHeights(stack)
    }

    private func lineHeights(_ stack: TextLayoutStack) -> [CGFloat] {
        lineHeights(stack.layoutManager, stack.container)
    }

    private func lineHeights(_ layoutManager: NSLayoutManager, _ container: NSTextContainer) -> [CGFloat] {
        lineFragments(layoutManager, container).map(\.height)
    }

    private func lineFragments(_ layoutManager: NSLayoutManager, _ container: NSTextContainer) -> [CGRect] {
        layoutManager.ensureLayout(for: container)
        var fragments: [CGRect] = []
        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var range = NSRange()
            fragments.append(layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &range))
            glyphIndex = NSMaxRange(range)
        }
        return fragments
    }

    private func plain(_ text: String, font: NSFont, multiple: CGFloat? = nil) -> NSAttributedString {
        NSAttributedString(string: text, attributes: TextLayoutStyle.textAttributes(
            font: font, alignment: .center, lineHeightMultiple: multiple, legacyLineSpacing: nil
        ))
    }

    @Test(arguments: [nil, 0.8, 1.3] as [CGFloat?])
    func fallbackOnlyLinesMatchLinesHoldingADeclaredGlyph(multiple: CGFloat?) throws {
        let font = try latinOnlyFont(size: 110)
        let heights = lineHeights(plain(Self.cyrillic, font: font, multiple: multiple), width: 826, multiple: multiple)
        #expect(heights.count == 3)
        #expect(Set(heights).count == 1, "\(heights)")
    }

    @Test func anAttributeOnlyEditKeepsTheDeclaredFont() throws {
        let font = try latinOnlyFont(size: 110)
        let stack = TextLayoutStack(containerSize: CGSize(width: 826, height: 10_000))
        stack.storage.setAttributedString(plain(Self.cyrillic, font: font))
        let before = lineHeights(stack)
        stack.storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 0, length: stack.storage.length))
        #expect(lineHeights(stack) == before)
        #expect(Set(before).count == 1, "\(before)")
    }

    @Test func latinLinesAreUnchanged() throws {
        let font = try latinOnlyFont(size: 110)
        let attributed = plain("Log any session in seconds", font: font)
        let heights = lineHeights(attributed, width: 826)
        let natural = NSLayoutManager()
        #expect(heights.allSatisfy { $0 == natural.defaultLineHeight(for: font) }, "\(heights)")
    }

    @Test(arguments: [-30, 20] as [CGFloat])
    func legacyLineSpacingIsKept(spacing: CGFloat) throws {
        let font = try latinOnlyFont(size: 110)
        let attributes = TextLayoutStyle.textAttributes(
            font: font, alignment: .center, lineHeightMultiple: nil, legacyLineSpacing: spacing
        )
        let latin = lineHeights(NSAttributedString(string: "Log any session in seconds", attributes: attributes), width: 826)
        let storage = NSTextStorage(string: "Log any session in seconds", attributes: attributes)
        let bare = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 826, height: 10_000))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        bare.addTextContainer(container)
        storage.addLayoutManager(bare)
        #expect(latin == lineHeights(bare, container))

        let cyrillic = lineHeights(NSAttributedString(string: Self.cyrillic, attributes: attributes), width: 826)
        #expect(cyrillic.count >= 2 && latin.count >= 2)
        #expect(cyrillic.last == latin.last, "\(cyrillic) vs \(latin)")
    }

    @Test func aResizeKeepsTheDeclaredFont() throws {
        let font = try latinOnlyFont(size: 110)
        let stack = TextLayoutStack(containerSize: CGSize(width: 826, height: 10_000))
        stack.storage.setAttributedString(plain(Self.cyrillic, font: font))
        _ = lineHeights(stack)
        let fullRange = NSRange(location: 0, length: stack.storage.length)
        stack.storage.beginEditing()
        stack.storage.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let current = value as? NSFont else { return }
            stack.storage.addAttribute(.font, value: current.withSize(80), range: range)
        }
        stack.storage.endEditing()
        let heights = lineHeights(stack)
        #expect(Set(heights).count == 1, "\(heights)")
    }

    @Test func encodingRestoresTheDeclaredFont() throws {
        let font = try latinOnlyFont(size: 110)
        let stack = TextLayoutStack(containerSize: CGSize(width: 826, height: 10_000))
        stack.storage.setAttributedString(plain(Self.cyrillic, font: font))
        _ = lineHeights(stack)
        let restored = LineMetricsLayoutDelegate.restoringDeclaredFonts(stack.storage)
        var fontNames = Set<String>()
        restored.enumerateAttribute(.font, in: NSRange(location: 0, length: restored.length)) { value, _, _ in
            if let font = value as? NSFont { fontNames.insert(font.fontName) }
        }
        #expect(fontNames == [font.fontName])
        var hasTag = false
        restored.enumerateAttribute(LineMetricsLayoutDelegate.declaredFontKey, in: NSRange(location: 0, length: restored.length)) { value, _, _ in
            if value != nil { hasTag = true }
        }
        #expect(!hasTag)
    }

    @Test func aLargerRunStillMakesItsLineTaller() throws {
        let small = try latinOnlyFont(size: 40)
        let attributed = NSMutableAttributedString(attributedString: plain("Small line\n", font: small))
        attributed.append(plain("Big", font: small.withSize(120)))
        let heights = lineHeights(attributed, width: 826)
        #expect(heights.count == 2)
        #expect(heights[1] > heights[0] * 2)
    }
    private func lineOrigins(_ stack: TextLayoutStack) -> [CGFloat] {
        lineFragments(stack.layoutManager, stack.container).map(\.minY)
    }

    /// The inline editor re-lays out from the edited line, not the top; a compressed line must land
    /// where a fresh layout of the same text puts it, keystroke after keystroke.
    @Test func compressedLinesStayPutWhenALaterLineIsEdited() throws {
        let font = try latinOnlyFont(size: 40)
        let attributed = NSMutableAttributedString(attributedString: plain("Webcam\n", font: font.withSize(80), multiple: 0.92))
        attributed.append(plain("widgets on your\nHome Screen", font: font, multiple: 0.92))
        let edited = TextLayoutStack(containerSize: CGSize(width: 826, height: 10_000), lineHeightMultiple: 0.92)
        edited.storage.setAttributedString(attributed)
        _ = lineOrigins(edited)

        for _ in 0..<3 {
            edited.storage.replaceCharacters(in: NSRange(location: 7, length: 0), with: "g")
            _ = lineOrigins(edited)
        }
        edited.storage.addAttribute(.foregroundColor, value: NSColor.red, range: NSRange(location: 26, length: 4))

        let fresh = TextLayoutStack(containerSize: CGSize(width: 826, height: 10_000), lineHeightMultiple: 0.92)
        fresh.storage.setAttributedString(edited.storage)
        #expect(lineOrigins(edited) == lineOrigins(fresh))
    }
}
