import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct TextFitMeasurerTests {
    private static let font = NSFont.systemFont(ofSize: 40, weight: .bold)

    private func input(_ text: String, width: CGFloat = 300, height: CGFloat = 60) -> TextFitInput {
        TextFitInput(
            size: CGSize(width: width, height: height), text: text, font: Self.font,
            alignment: .center, uppercase: false, letterSpacing: nil,
            lineHeightMultiple: nil, legacyLineSpacing: nil, richTextData: nil
        )
    }

    @Test func shortTextFits() {
        #expect(TextFitMeasurer.fits(input("Hello")))
        #expect(!TextFitMeasurer.overflows(input("Hello"), shrinksToFit: false))
    }

    @Test func wrappedTextOverflowsAShortBox() {
        let long = input("Your screenshots in every language")
        #expect(!TextFitMeasurer.fits(long))
        #expect(TextFitMeasurer.fits(input("Your screenshots in every language", height: 400)))
    }

    @Test func overflowFlipsAsTheBoxShrinks() {
        let text = "Two lines\nof text"
        #expect(TextFitMeasurer.fits(input(text, height: 200)))
        #expect(!TextFitMeasurer.fits(input(text, height: 50)))
    }

    @Test func fitScaleShrinksUntilEveryLineFits() {
        let long = input("Your screenshots in every language")
        let scale = TextFitMeasurer.fitScale(long)
        #expect(scale < 1)
        #expect(scale >= TextFitMeasurer.minimumShrinkScale)
        #expect(TextFitMeasurer.fits(long, fontScale: scale))
        #expect(!TextFitMeasurer.overflows(long, shrinksToFit: true))
    }

    @Test func fitScaleIsOneWhenTextAlreadyFits() {
        #expect(TextFitMeasurer.fitScale(input("Hi")) == 1)
    }

    @Test func shrinkingStillOverflowsPastTheFloor() {
        let huge = input(String(repeating: "Lorem ipsum dolor sit amet ", count: 30))
        #expect(TextFitMeasurer.fitScale(huge) == TextFitMeasurer.minimumShrinkScale)
        #expect(TextFitMeasurer.overflows(huge, shrinksToFit: true))
    }

    @Test func emptyTextNeverOverflows() {
        #expect(TextFitMeasurer.fits(input("", height: 1)))
    }

    @Test func scaledAttributedStringShrinksEveryRun() {
        let attributed = NSMutableAttributedString(string: "ab", attributes: [.font: NSFont.systemFont(ofSize: 20), .kern: CGFloat(4)])
        attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 40), range: NSRange(location: 1, length: 1))
        let scaled = RichTextUtils.scaled(attributed, by: 0.5)
        #expect((scaled.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 10)
        #expect((scaled.attribute(.font, at: 1, effectiveRange: nil) as? NSFont)?.pointSize == 20)
        #expect((scaled.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat) == 2)
    }

    // MARK: - Locale overflow

    private func localizedState(for shape: CanvasShapeModel, german: String) -> LocaleState {
        LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "de", label: "German")],
            activeLocaleCode: "en",
            overrides: ["de": [shape.textTranslationKey: ShapeLocaleOverride(text: german)]]
        )
    }

    @Test func longTranslationOverflowsWhileBaseFits() {
        let shape = CanvasShapeModel(type: .text, width: 400, height: 70, text: "Edit fast", fontSize: 40, fontWeight: 700)
        let state = localizedState(for: shape, german: "Bearbeite deine Bildschirmfotos blitzschnell und mühelos")
        let families = PlatformFonts.familyNameSet
        #expect(!TextOverflowCheck.overflows(shape, localeCode: "en", localeState: state, availableFontFamilies: families))
        #expect(TextOverflowCheck.overflows(shape, localeCode: "de", localeState: state, availableFontFamilies: families))

        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 400, templateHeight: 800)
        row.shapes = [shape]
        #expect(TextOverflowCheck.overflowingLocaleCodes(in: row, localeState: state, availableFontFamilies: families) == ["de"])
        let issues = TextOverflowCheck.uploadIssues(rows: [row], localeState: state)
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .warning)
    }

    @Test func shrinkToFitClearsTheOverflow() {
        var shape = CanvasShapeModel(type: .text, width: 400, height: 70, text: "Edit fast", fontSize: 40, fontWeight: 700)
        shape.shrinkToFit = true
        let state = localizedState(for: shape, german: "Bearbeite Bildschirmfotos blitzschnell")
        #expect(!TextOverflowCheck.overflows(shape, localeCode: "de", localeState: state, availableFontFamilies: PlatformFonts.familyNameSet))
    }

    @Test func shrinkToFitRoundTripsAndDefaultsOff() throws {
        var shape = CanvasShapeModel(type: .text, text: "Hi")
        shape.shrinkToFit = true
        let data = try JSONEncoder().encode(shape)
        #expect(String(data: data, encoding: .utf8)?.contains("\"stf\":true") == true)
        #expect(try JSONDecoder().decode(CanvasShapeModel.self, from: data).shrinkToFit == true)

        let legacy = try JSONEncoder().encode(CanvasShapeModel(type: .text, text: "Hi"))
        #expect(String(data: legacy, encoding: .utf8)?.contains("stf") == false)
        #expect(try JSONDecoder().decode(CanvasShapeModel.self, from: legacy).shrinkToFit == nil)
    }
}
