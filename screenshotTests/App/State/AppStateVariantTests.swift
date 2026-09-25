import Foundation
@testable import Screenshot_Bro
import SwiftUI
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

    @Test func aVariantTakesOneRowPerScreenshotSize() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))

        state.duplicateRow(source.id, into: variantId)
        #expect(state.rows.inVariant(variantId).count == 1, "copying a second row of the same size is refused")

        state.setRowVariant(source.id, to: variantId)
        #expect(state.rows.first { $0.id == source.id }?.isOriginal == true, "moving one in is refused too")
        #expect(state.rowOccupyingSlot(of: source, in: variantId) != nil)
        #expect(state.rowOccupyingSlot(of: source, in: nil) == nil, "the Original has no per-size limit")
    }

    @Test func variantRowsCannotBeRenamed() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        state.updateRowLabel(source.id, text: "Welcome")
        _ = state.createVariant(fromRow: source.id)
        let variantRow = state.rows[1]

        state.updateRowLabel(variantRow.id, text: "Custom")

        #expect(state.rows[1].label == variantRow.label)
    }

    @Test func aRowMovedIntoAVariantKeepsItsOwnEditableLabel() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.deleteRows([state.rows[1].id])
        state.updateRowLabel(source.id, text: "Hero")

        state.setRowVariant(source.id, to: variantId)
        state.updateRowLabel(source.id, text: "Renamed")

        #expect(state.rows.first { $0.id == source.id }?.label == "Renamed")
    }

    @Test func renamingTheSourceRowRenamesItsVariantCopies() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let b = try #require(state.createVariant(fromRow: source.id))
        let copyB = try #require(state.rows.inVariant(b).first)
        let c = try #require(state.createVariant(fromRow: copyB.id))

        state.updateRowLabel(source.id, text: "Welcome")

        #expect(state.rows.inVariant(b).first?.label == "Welcome")
        #expect(state.rows.inVariant(c).first?.label == "Welcome", "a copy of a copy follows the same source")
    }

    @Test func aRowAddedInsideAVariantCanBeRenamed() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.addRow(variantId: variantId)
        let added = try #require(state.rows.last)

        state.updateRowLabel(added.id, text: "Extra")

        #expect(state.rows.last?.label == "Extra")
    }

    @Test func deletingTheSourceUnlocksItsCopies() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        state.addRowBelow(source.id)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.deleteRow(source.id)
        let copy = try #require(state.rows.inVariant(variantId).first)

        state.updateRowLabel(copy.id, text: "Free")

        #expect(state.rows.inVariant(variantId).first?.label == "Free")
    }

    @Test func resettingALinkedCopyKeepsFollowingItsSource() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        state.updateRowLabel(source.id, text: "Welcome")
        let variantId = try #require(state.createVariant(fromRow: source.id))
        let copy = try #require(state.rows.inVariant(variantId).first)

        state.resetRow(copy.id)
        state.updateRowLabel(source.id, text: "Hello")

        #expect(state.rows.inVariant(variantId).first?.label == "Hello")
    }

    @Test func excludedRowsDoNotTakeAVariantSlot() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        let copyIndex = try #require(state.rows.firstIndex { $0.variantId == variantId })
        state.rows[copyIndex].excludeFromAppStoreConnect = true

        #expect(state.rowOccupyingSlot(of: source, in: variantId) == nil)
        state.duplicateRow(source.id, into: variantId)
        #expect(state.variantSlotOccupancy().clashing.isEmpty)
    }

    @Test func aNewVariantNeverTakesAnExistingNameInAnotherCase() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let first = try #require(state.createVariant(fromRow: source.id))
        state.renameVariant(first, to: "variant b")

        _ = state.createVariant(fromRow: source.id)

        let names = state.variants.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test func copyingIntoAFilteredOutVariantWidensTheFilter() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        state.setVariantFilter(.variant(nil))

        _ = state.createVariant(fromRow: source.id)

        #expect(state.viewMode.variantFilter == .all)
    }

    @Test func filteringMovesTheSelectionOffAHiddenRow() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        #expect(state.selectedRowId == state.rows[1].id)

        state.setVariantFilter(.variant(nil))

        #expect(state.selectedRowId == source.id)
        _ = variantId
    }

    @Test func variantsKeepTheirColourSlotWhenAnotherIsDeleted() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let b = try #require(state.createVariant(fromRow: source.id))
        _ = try #require(state.createVariant(fromRow: source.id))
        let slotC = state.variants[1].colorIndex

        state.deleteVariant(b)

        #expect(state.variants.first?.colorIndex == slotC)
    }

    @Test func variantRowsCannotBeDuplicatedInPlace() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        _ = state.createVariant(fromRow: source.id)
        let variantRow = state.rows[1]

        state.duplicateRow(variantRow.id)

        #expect(state.rows.count == 2)
    }

    @Test func aSizeClashInsideAVariantIsReported() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        #expect(state.variantSlotOccupancy().clashing.isEmpty)

        state.addRowBelow(state.rows[1].id)
        let added = try #require(state.rows.first { $0.variantId == variantId && $0.id != state.rows[1].id })
        let rowIndex = try #require(state.rowIndex(for: added.id))
        state.resizeRow(at: rowIndex, newWidth: source.templateWidth, newHeight: source.templateHeight)

        #expect(state.variantSlotOccupancy().clashing == Set(state.rows.inVariant(variantId).map(\.id)))
    }

    @Test func renamingToATakenNameNumbersIt() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let b = try #require(state.createVariant(fromRow: source.id))
        let c = try #require(state.createVariant(fromRow: source.id))

        state.renameVariant(c, to: "variant b")
        #expect(state.variants.first { $0.id == c }?.name == "variant b 2")

        state.renameVariant(b, to: "Original")
        #expect(state.variants.first { $0.id == b }?.name == "Original 2")
    }

    @Test func deletingTheSelectedRowUnderAFilterSelectsAVisibleOne() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        state.addRowBelow(source.id)
        let second = state.rows[1].id
        _ = state.createVariant(fromRow: second)
        // Original, Original, B — filtered to the Original, delete the second row.
        state.setVariantFilter(.variant(nil))
        state.selectRow(second)

        state.deleteRow(second)

        #expect(state.selectedRowId == source.id)
    }

    @Test func aCopyOfAnAutoLabelledRowIsNamedOnItsOwn() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        #expect(!source.isLabelManuallySet)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        let copy = try #require(state.rows.inVariant(variantId).first)

        state.updateRowLabel(copy.id, text: "Bold")
        state.updateRowLabel(source.id, text: "Welcome")

        #expect(state.rows.inVariant(variantId).first?.label == "Bold", "a copy named by hand no longer follows")
    }

    @Test func aVariantCopyLeavesItsSharedTranslationGroup() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        var text = CanvasShapeModel(type: .text, x: 10, y: 10, width: 200, height: 80, color: .black, text: "Hello", fontSize: 40, fontWeight: 700)
        text.translationKey = "shared-key"
        let rowIndex = try #require(state.rowIndex(for: source.id))
        state.rows[rowIndex].shapes.append(text)

        let variantId = try #require(state.createVariant(fromRow: source.id))

        let copiedText = try #require(state.rows.inVariant(variantId).first?.shapes.first { $0.type == .text && $0.text == "Hello" })
        #expect(copiedText.translationKey == nil)
        #expect(state.rows[rowIndex].shapes.last?.translationKey == "shared-key", "the Original keeps its group")
    }

    @Test func undoUnderAFilterKeepsTheSelectionVisible() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let source = try #require(state.rows.first)
        let variantId = try #require(state.createVariant(fromRow: source.id))
        state.setVariantFilter(.variant(variantId))
        state.addRow(variantId: variantId)

        state.undoDocumentAction()

        let selected = try #require(state.selectedRow)
        #expect(state.effectiveVariantFilter.includes(selected))
    }
}
