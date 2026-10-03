import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    // MARK: - Selection

    @Test func selectRowClearsShapeSelection() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)
        #expect(state.selectedShapeId == shape.id)

        state.addRow()
        state.selectRow(state.rows.last!.id)
        #expect(state.selectedShapeId == nil, "Shape selection cleared when switching rows")
    }

    @Test func deselectAllClearsEverything() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        state.addShape(CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344))

        state.deselectAll()
        #expect(state.selectedRowId == nil)
        #expect(state.selectedShapeId == nil)
    }

    @Test func selectShapeAlsoSelectsRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        let row2Id = state.rows[1].id
        state.selectRow(row2Id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        // Select a shape in row 2 while row 1 is selected
        state.selectRow(state.rows[0].id)
        state.selectShape(shape.id, in: row2Id)
        #expect(state.selectedRowId == row2Id)
        #expect(state.selectedShapeId == shape.id)
    }

    @Test func selectShapesSetsRowAndIds() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let a = CanvasShapeModel.defaultRectangle(centerX: 400, centerY: 800)
        let b = CanvasShapeModel.defaultCircle(centerX: 800, centerY: 800)
        state.addShape(a)
        state.addShape(b)

        state.selectShapes([a.id, b.id], in: rowId)
        #expect(state.selectedRowId == rowId)
        #expect(state.selectedShapeIds == [a.id, b.id])
    }

    @Test func selectShapesSwitchesRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addRow()
        let row2Id = state.rows[1].id
        state.selectRow(row2Id)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        state.selectRow(state.rows[0].id)
        state.selectShapes([shape.id], in: row2Id)
        #expect(state.selectedRowId == row2Id)
        #expect(state.selectedShapeIds == [shape.id])
    }

    @Test func selectShapesIgnoresUnknownRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        state.selectShapes([shape.id], in: UUID())
        #expect(state.selectedRowId == rowId, "Unknown row leaves selection untouched")
        #expect(state.selectedShapeIds == [shape.id])
    }

    /// The marquee calls `selectShapes` on every drag tick; a repeat call must be inert so the
    /// row body only re-evaluates when the swept set actually changes.
    @Test func selectShapesWithSameSetIsANoOp() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)
        state.selectShapes([shape.id], in: rowId)

        state.selectShapes([shape.id], in: rowId)
        #expect(state.selectedRowId == rowId)
        #expect(state.selectedShapeIds == [shape.id])
    }

    @Test func selectShapesWithEmptySetClearsButKeepsRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        state.selectShapes([], in: rowId)
        #expect(state.selectedShapeIds.isEmpty)
        #expect(state.selectedRowId == rowId, "An empty sweep still leaves the row selected")
    }

    /// A sweep landing on exactly the shape being edited is a no-op for the id set, but must
    /// still close the inline editor — otherwise the band draws over a live text view.
    @Test func selectShapesEndsTextEditingEvenWhenSetIsUnchanged() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        state.addShape(shape)
        state.selectShapes([shape.id], in: rowId)
        state.textEdit.isActive = true

        state.selectShapes([shape.id], in: rowId)
        #expect(state.textEdit.isActive == false)
        #expect(state.selectedShapeIds == [shape.id])
    }

    /// The row's membership invariant holds by construction, not by trusting the caller —
    /// `normalizeSelection` enforces the same thing after mutations.
    @Test func selectShapesDropsIdsNotInTheRow() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)
        let shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        state.addShape(shape)

        state.selectShapes([shape.id, UUID()], in: rowId)
        #expect(state.selectedShapeIds == [shape.id])
    }

    // MARK: - Background image references

    /// A background image config outlives its style so toggling back doesn't lose it. Retention
    /// must still see the reference (or cleanup deletes the file), but the render path must not:
    /// counting it would let a file nothing draws report itself as a missing resource and abort
    /// an App Store Connect / Google Play upload.
    @Test func inactiveBackgroundImageCountsForRetentionButNotForRendering() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = try #require(state.rows.first?.id)
        let localeCode = state.localeState.activeLocaleCode

        state.saveBackgroundImage(makeSolidImage(.systemBlue, width: 100, height: 100), for: rowId)
        let fileName = try #require(state.rows.first?.backgroundImageConfig.fileName)
        state.rows[0].backgroundStyle = .image
        #expect(state.referencedImageFileNames(forRow: state.rows[0], localeCode: localeCode).contains(fileName))

        state.rows[0].backgroundStyle = .color
        #expect(state.rows.first?.backgroundImageConfig.fileName == fileName, "The config is kept for toggling back")
        #expect(
            !state.referencedImageFileNames(forRow: state.rows[0], localeCode: localeCode).contains(fileName),
            "An inactive background image is not a render resource"
        )
        #expect(
            state.allReferencedImageFileNames().contains(fileName),
            "…but retention still sees it, so cleanup must not delete the file"
        )
    }

    /// The same rule for a per-template override: it only paints while the override is on.
    @Test func templateBackgroundImageIsInactiveWhileOverrideIsOff() throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        let rowId = try #require(state.rows.first?.id)
        let localeCode = state.localeState.activeLocaleCode

        state.saveBackgroundImage(makeSolidImage(.systemBlue, width: 100, height: 100), for: rowId, templateIndex: 0)
        let fileName = try #require(state.rows.first?.templates.first?.backgroundImageConfig.fileName)

        state.rows[0].templates[0].backgroundStyle = .image
        state.rows[0].templates[0].overrideBackground = true
        #expect(state.referencedImageFileNames(forRow: state.rows[0], localeCode: localeCode).contains(fileName))

        state.rows[0].templates[0].overrideBackground = false
        #expect(!state.referencedImageFileNames(forRow: state.rows[0], localeCode: localeCode).contains(fileName))
        #expect(state.allReferencedImageFileNames().contains(fileName))
    }
}
