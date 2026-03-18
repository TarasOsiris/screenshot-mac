import Testing
import AppKit
@testable import Screenshot_Bro

@MainActor
@Suite(.serialized)
struct AppStateLocaleTests {

    @Test func resetTranslationRemovesOverrideFromProgress() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shapeId = try #require(state.rows.first?.shapes.first(where: { $0.type == .text })?.id)

        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.translationProgress() == (0, 1))

        state.updateTranslationText(shapeId: shapeId, text: "Bonjour")
        #expect(state.translationProgress() == (1, 1))

        state.resetTranslationText(shapeId: shapeId)
        #expect(state.translationProgress() == (0, 1))
    }

}
