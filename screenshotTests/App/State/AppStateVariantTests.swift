import Foundation
@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
@MainActor
struct AppStateVariantTests {

    private func makeState() -> (AppState, URL) { makeTestState() }
    private func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }

    @Test func createVariantCopiesRowIntoNewVariant() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)

        let variantId = try #require(state.createVariant(fromRow: source.id))

        #expect(state.variants.map(\.id) == [variantId])
        #expect(state.variants[0].name == String(localized: "Variant B"))
        #expect(state.rows.count == 2)
        let copy = state.rows[1]
        #expect(copy.variantId == variantId)
        #expect(copy.label == source.label)
        #expect(copy.shapes.count == source.shapes.count)
        #expect(Set(copy.shapes.map(\.id)).isDisjoint(with: source.shapes.map(\.id)))
        #expect(state.rows[0].isOriginal)
        #expect(state.selectedRowId == copy.id)
    }

    @Test func createVariantCopiesLocaleOverridesToNewShapeIds() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let shapeId = try #require(source.shapes.first?.id)
        state.localeState.overrides["de"] = [shapeId.uuidString: ShapeLocaleOverride(text: "Hallo")]

        _ = try #require(state.createVariant(fromRow: source.id))

        let copiedShapeId = try #require(state.rows[1].shapes.first?.id)
        #expect(state.localeState.overrides["de"]?[copiedShapeId.uuidString]?.text == "Hallo")
    }

    @Test func createVariantIsOneUndoStepCoveringRowsAndVariants() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)

        _ = state.createVariant(fromRow: source.id)
        #expect(state.variants.count == 1)

        state.undoDocumentAction()
        #expect(state.variants.isEmpty)
        #expect(state.rows.map(\.id) == [source.id])

        state.redoDocumentAction()
        #expect(state.variants.count == 1)
        #expect(state.rows.count == 2)
    }

    @Test func secondVariantTakesNextLetter() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)

        _ = state.createVariant(fromRow: source.id)
        _ = state.createVariant(fromRow: source.id)

        #expect(state.variants.map(\.name) == [String(localized: "Variant B"), String(localized: "Variant C")])
    }

    @Test func setRowVariantMovesRowAndRejectsUnknownVariant() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))

        state.setRowVariant(source.id, to: variantId)
        #expect(state.rows[0].variantId == variantId)

        state.setRowVariant(source.id, to: UUID())
        #expect(state.rows[0].variantId == variantId)

        state.setRowVariant(source.id, to: nil)
        #expect(state.rows[0].isOriginal)
    }

    @Test func deleteVariantRemovesItsRows() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))

        state.deleteVariant(variantId)

        #expect(state.variants.isEmpty)
        #expect(state.rows.map(\.id) == [source.id])
    }

    @Test func deleteVariantOwningEveryRowMovesThemToOriginal() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.deleteRow(source.id)
        #expect(state.rows.count == 1)

        state.deleteVariant(variantId)

        #expect(state.variants.isEmpty)
        #expect(state.rows.count == 1)
        #expect(state.rows[0].isOriginal)
    }

    @Test func resetRowKeepsVariant() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        let variantRowId = state.rows[1].id

        state.resetRow(variantRowId)

        #expect(state.rows[1].variantId == variantId)
    }

    @Test func renameVariantTrimsAndIgnoresBlank() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))

        state.renameVariant(variantId, to: "  Dark hero  ")
        #expect(state.variants[0].name == "Dark hero")

        state.renameVariant(variantId, to: "   ")
        #expect(state.variants[0].name == "Dark hero")
    }

    @Test func variantsSurviveSaveAndReload() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.saveAll()

        let projectId = try #require(state.activeProjectId)
        let data = try #require(PersistenceService.loadProject(projectId))

        #expect(data.variants.map(\.id) == [variantId])
        #expect(data.rows.map(\.variantId) == [nil, variantId])
    }

    @Test func variantRowsAreLeftOutOfTheAppStoreListing() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        _ = state.createVariant(fromRow: source.id)

        #expect(state.rows.map(\.uploadsToAppStoreListing) == [true, false])
    }

    @Test func movingARowUnderAVariantFilterSkipsHiddenRows() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let first = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: first.id))
        state.duplicateRow(state.rows[1].id, into: nil)
        state.duplicateRow(state.rows[2].id, into: variantId)
        // Original, B, Original, B
        #expect(state.rows.map(\.variantId) == [nil, variantId, nil, variantId])
        let lastVariantRow = state.rows[3].id

        state.moveRowUp(lastVariantRow, among: EditorVariantFilter.variant(variantId).includes)

        #expect(state.rows[1].id == lastVariantRow)
        #expect(state.rows.map(\.variantId) == [nil, variantId, nil, variantId])
    }

    @Test func createVariantKeepsAnAutomaticLabelAutomatic() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        #expect(!source.isLabelManuallySet)

        _ = state.createVariant(fromRow: source.id)

        #expect(state.rows[1].isLabelManuallySet == false)
    }
}
