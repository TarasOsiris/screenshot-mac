import AppKit
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct TextAutoFitServiceTests {
    private static let longGerman = "Bearbeite deine Bildschirmfotos blitzschnell und mühelos"
    private let families = PlatformFonts.familyNameSet

    private func textShape(
        y: CGFloat = 300, width: CGFloat = 300, height: CGFloat = 60,
        align: TextVerticalAlign = .center, rotation: Double = 0
    ) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .text, x: 50, y: y, width: width, height: height, rotation: rotation,
            text: "Edit fast", fontSize: 40, fontWeight: 700, textVerticalAlign: align
        )
    }

    private func localeState(for shape: CanvasShapeModel, german: String) -> LocaleState {
        LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "de", label: "German")],
            activeLocaleCode: "en",
            overrides: ["de": [shape.textTranslationKey: ShapeLocaleOverride(text: german)]]
        )
    }

    private func row(_ shapes: [CanvasShapeModel], height: CGFloat = 800) -> ScreenshotRow {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 400, templateHeight: height)
        row.shapes = shapes
        return row
    }

    private func fit(_ shape: CanvasShapeModel, german: String, in row: ScreenshotRow) -> TextAutoFitResult {
        TextAutoFitService.fit(
            shape: shape, localeCode: "de", row: row,
            localeState: localeState(for: shape, german: german), availableFontFamilies: families
        )
    }

    @Test func fittingTextIsLeftAlone() {
        let shape = textShape()
        #expect(fit(shape, german: "Schnell", in: row([shape])) == .unchanged)
    }

    @Test func slightOverflowOnlyShrinks() {
        let word = "Bildschirmfotos"
        let font = NSFont.systemFont(ofSize: 40, weight: .bold)
        let wordWidth = (word as NSString).size(withAttributes: [.font: font]).width
        let shape = textShape(width: (wordWidth * 0.9).rounded(.down))

        let result = fit(shape, german: word, in: row([shape]))
        #expect(result.action == .shrink)
        #expect(!result.enablesShrinkToFit, "plain text shrinks through this locale's font size, never the shared flag")
        #expect(result.contribution.fontSize.map { $0 < 40 } == true)
        #expect(result.fontScale >= TextAutoFitService.preferredMinimumScale)
        #expect(result.contribution.addedHeight == 0)
        #expect(!result.stillOverflows)
    }

    @Test(arguments: [TextVerticalAlign.top, .center, .bottom])
    func longOverflowGrowsTheBoxAroundItsAnchor(align: TextVerticalAlign) {
        let shape = textShape(align: align)
        let result = fit(shape, german: Self.longGerman, in: row([shape]))

        #expect(result.action == .grow || result.action == .growAndShrink)
        #expect(result.contribution.addedHeight > 0)
        #expect(result.fontScale >= TextAutoFitService.preferredMinimumScale)
        #expect(!result.stillOverflows)
        switch align {
        case .top: #expect(result.contribution.offsetY == 0)
        case .center: #expect(abs(result.contribution.offsetY + result.contribution.addedHeight / 2) < 0.001)
        case .bottom: #expect(result.contribution.offsetY == -result.contribution.addedHeight)
        }
    }

    @Test func growthStopsAtTheShapeBelowAndTheCanvasTop() {
        let shape = textShape(y: 40, align: .top)
        let device = CanvasShapeModel(type: .rectangle, x: 0, y: 120, width: 400, height: 600)
        let result = fit(shape, german: Self.longGerman, in: row([shape, device]))

        let top = shape.y + result.contribution.offsetY
        let bottom = top + shape.height + result.contribution.addedHeight
        #expect(top >= 0)
        #expect(bottom <= device.y + 0.001)
        #expect(result.contribution.addedHeight <= 60 + 0.001)
    }

    @Test func shapesTheBoxAlreadyOverlapsAreNotObstacles() {
        let shape = textShape(align: .top)
        let backdrop = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 400, height: 800)
        let result = fit(shape, german: Self.longGerman, in: row([backdrop, shape]))
        #expect(result.contribution.addedHeight > 0)
        #expect(!result.stillOverflows)
    }

    @Test func boxedInTextOnlyShrinks() {
        let shape = textShape(y: 100)
        let above = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 400, height: 100)
        let below = CanvasShapeModel(type: .rectangle, x: 0, y: 160, width: 400, height: 640)
        let result = fit(shape, german: Self.longGerman, in: row([above, shape, below]))
        #expect(result.action == .shrink)
        #expect(result.contribution.addedHeight == 0)
    }

    @Test func rotatedTextOnlyShrinks() {
        let shape = textShape(rotation: 10)
        let result = fit(shape, german: Self.longGerman, in: row([shape]))
        #expect(result.action == .shrink)
        #expect(result.contribution.addedHeight == 0)
    }

    @Test func impossibleTextReportsTheOverflow() {
        let shape = textShape(y: 0, height: 60)
        let huge = String(repeating: "Lorem ipsum dolor sit amet ", count: 30)
        let result = fit(shape, german: huge, in: row([shape], height: 120))
        #expect(result.stillOverflows)
        #expect(result.fontScale == TextFitMeasurer.minimumShrinkScale)
    }

    @Test func richTextShrinksOnlyWhenNoOtherLocaleWould() throws {
        let word = "Bildschirmfotos"
        let font = NSFont.systemFont(ofSize: 40, weight: .bold)
        let wordWidth = (word as NSString).size(withAttributes: [.font: font]).width
        var shape = textShape(width: (wordWidth * 0.9).rounded(.down))
        shape.richText = try #require(RichTextUtils.encode(NSAttributedString(string: "Edit", attributes: [.font: font])))
        var state = localeState(for: shape, german: word)
        state.overrides["de"]?[shape.textTranslationKey]?.richText = RichTextUtils.encode(
            NSAttributedString(string: word, attributes: [.font: font])
        )

        let alone = TextAutoFitService.fit(shape: shape, localeCode: "de", row: row([shape]), localeState: state, availableFontFamilies: families)
        #expect(alone.enablesShrinkToFit)

        state.locales.append(.init(code: "fr", label: "French"))
        state.overrides["fr"] = [shape.textTranslationKey: ShapeLocaleOverride(text: Self.longGerman)]
        let crowded = TextAutoFitService.fit(shape: shape, localeCode: "de", row: row([shape]), localeState: state, availableFontFamilies: families)
        #expect(!crowded.enablesShrinkToFit, "French would silently shrink to half size with it")
    }

    // MARK: - AppState

    private func stateWithHeadline() -> (AppState, URL, CanvasShapeModel, CanvasShapeModel) {
        let (state, tempDir) = makeTestState()
        var shape = textShape(align: .top)
        shape.translationKey = "headline"
        var twin = textShape(y: 500, align: .top)
        twin.translationKey = "headline"
        state.rows[0].shapes = [shape, twin]
        state.addLocale(LocaleDefinition(code: "de", label: "German"))
        return (state, tempDir, shape, twin)
    }

    private func setGerman(_ text: String, on shape: CanvasShapeModel, in state: AppState) {
        state.setTranslation(shapeId: shape.id, localeCode: "de", text: text)
    }

    @Test func appliesPerLocaleGeometryAndUndoesInOneStep() throws {
        let (state, tempDir, shape, twin) = stateWithHeadline()
        defer { cleanupTestState(tempDir) }
        let before = state.document

        setGerman(Self.longGerman, on: shape, in: state)

        for id in [shape.id, twin.id] {
            let base = try #require(state.rows[0].shapes.first { $0.id == id })
            #expect(base.y == (id == shape.id ? shape.y : twin.y))
            #expect(base.height == 60)
            #expect(base.shrinkToFit == nil)
            let german = LocaleService.resolveShape(base, localeCode: "de", localeState: state.localeState)
            #expect(german.height > 60)
            #expect(TextOverflowCheck.overflowingLocaleCodes(
                of: base, localeState: state.localeState, availableFontFamilies: state.availableFontFamilySet
            ).isEmpty)
        }

        state.undoDocumentAction()
        #expect(state.document == before)
    }

    @Test func shorterOrClearedTranslationGivesTheSpaceBack() throws {
        let (state, tempDir, shape, _) = stateWithHeadline()
        defer { cleanupTestState(tempDir) }

        setGerman(Self.longGerman, on: shape, in: state)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.autoFit != nil)

        setGerman("Schnell", on: shape, in: state)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id) == nil)

        setGerman(Self.longGerman, on: shape, in: state)
        setGerman("", on: shape, in: state)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id) == nil)
    }

    @Test func refittingKeepsAUsersOwnLocaleOffset() throws {
        let (state, tempDir, shape, _) = stateWithHeadline()
        defer { cleanupTestState(tempDir) }
        LocaleService.setShapeOverride(&state.localeState, localeCode: "de", shapeId: shape.id, override: ShapeLocaleOverride(offsetX: 12))

        setGerman(Self.longGerman, on: shape, in: state)
        setGerman("Schnell", on: shape, in: state)

        #expect(state.localeState.override(forCode: "de", shapeId: shape.id) == ShapeLocaleOverride(offsetX: 12))
    }
}
