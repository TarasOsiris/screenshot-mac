import Foundation
@testable import Screenshot_Bro
import Testing

/// Pure-value suite — no `makeTestState`, so no shared data directory and no `.serialized`.
@MainActor
struct InspectorContentTests {
    private func row(shapeCount: Int) -> ScreenshotRow {
        ScreenshotRow(
            templates: [ScreenshotTemplate()],
            shapes: (0..<shapeCount).map { _ in CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10) }
        )
    }

    @Test func noRowIsEmpty() {
        let content = InspectorContent.resolve(row: nil, selectedShapeIds: [UUID()], previewingRows: [], includesShapes: true)
        #expect(content == .empty)
    }

    @Test func rowWithoutShapeSelectionShowsTheRow() {
        let row = row(shapeCount: 2)
        let content = InspectorContent.resolve(row: row, selectedShapeIds: [], previewingRows: [], includesShapes: true)
        #expect(content == .row)
    }

    /// A previewing row can't be edited, so it keeps its preview panel.
    @Test func previewKeepsTheRowOverAShapeSelection() {
        let row = row(shapeCount: 2)
        let content = InspectorContent.resolve(
            row: row, selectedShapeIds: [row.shapes[0].id], previewingRows: [row.id], includesShapes: true
        )
        #expect(content == .row)
    }

    @Test func oneSelectedShapeShowsTheShape() {
        let row = row(shapeCount: 2)
        let shapeId = row.shapes[1].id
        let content = InspectorContent.resolve(row: row, selectedShapeIds: [shapeId], previewingRows: [], includesShapes: true)
        #expect(content == .shape(shapeId))
    }

    @Test func severalSelectedShapesShowTheGroup() {
        let row = row(shapeCount: 3)
        let ids = Set(row.shapes.prefix(2).map(\.id))
        let content = InspectorContent.resolve(row: row, selectedShapeIds: ids, previewingRows: [], includesShapes: true)
        #expect(content == .shapes)
    }

    /// A selection id from another row, or one just deleted, must not count toward single vs multi.
    @Test func staleIdsAreIgnored() {
        let row = row(shapeCount: 2)
        let shapeId = row.shapes[0].id
        #expect(
            InspectorContent.resolve(row: row, selectedShapeIds: [UUID()], previewingRows: [], includesShapes: true)
                == .row
        )
        #expect(
            InspectorContent.resolve(row: row, selectedShapeIds: [shapeId, UUID()], previewingRows: [], includesShapes: true)
                == .shape(shapeId)
        )
    }

    /// With the setting off (and always on iPad) shape properties stay in the bottom bar.
    @Test func withoutShapesTheRowStaysVisible() {
        let row = row(shapeCount: 2)
        let content = InspectorContent.resolve(
            row: row, selectedShapeIds: Set(row.shapes.map(\.id)), previewingRows: [], includesShapes: false
        )
        #expect(content == .row)
    }

    @Test func propertiesBarStepsAsideOnlyWhileAnOpenInspectorShowsTheShapes() {
        #expect(!InspectorContent.showsPropertiesBar(hasShapeSelection: false, inspectorShowsShapes: false, inspectorPresented: true))
        #expect(InspectorContent.showsPropertiesBar(hasShapeSelection: true, inspectorShowsShapes: false, inspectorPresented: true))
        #expect(!InspectorContent.showsPropertiesBar(hasShapeSelection: true, inspectorShowsShapes: true, inspectorPresented: true))
        // A hidden sidebar would otherwise leave a selected shape with no properties anywhere.
        #expect(InspectorContent.showsPropertiesBar(hasShapeSelection: true, inspectorShowsShapes: true, inspectorPresented: false))
    }

    /// The bar and the inspector must agree: a previewing row shows no shape properties, so the bar does.
    @Test func previewingRowNeverHidesTheBar() {
        let showsShapes = InspectorContent.showsShapeProperties(includesShapes: true, rowIsPreviewing: true)
        #expect(!showsShapes)
        #expect(InspectorContent.showsPropertiesBar(hasShapeSelection: true, inspectorShowsShapes: showsShapes, inspectorPresented: true))
    }
}
