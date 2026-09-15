import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

@Suite(.serialized)
@MainActor
struct AppStateInsertShapeTests {

    @Test func insertedShapeLandsInTheRowAndIsSelected() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let rowId = state.rows.first!.id
        let before = state.rows.first!.shapes.count

        state.insertDefaultShape(.star, inRow: rowId)

        let shapes = state.rows.first!.shapes
        #expect(shapes.count == before + 1)
        #expect(shapes.last?.type == .star)
        #expect(state.selectedRowId == rowId)
        #expect(state.selectedShapeIds == [shapes.last!.id])
    }

    @Test func explicitCenterIsHonoured() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let rowId = state.rows.first!.id

        state.insertDefaultShape(.rectangle, inRow: rowId, at: CGPoint(x: 500, y: 700))

        let shape = state.rows.first!.shapes.last!
        #expect(abs(shape.x + shape.width / 2 - 500) < 1)
        #expect(abs(shape.y + shape.height / 2 - 700) < 1)
    }

    @Test func unknownRowOrSvgWithoutContentAddsNothing() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let rowId = state.rows.first!.id
        let before = state.rows.first!.shapes.count

        state.insertDefaultShape(.rectangle, inRow: UUID())
        state.insertDefaultShape(.svg, inRow: rowId)

        #expect(state.rows.first!.shapes.count == before)
    }

    @Test func svgInsertAppliesCustomColourAndScalesDown() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = state.rows.first!
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4000 4000"><rect width="4000" height="4000"/></svg>"#

        state.insertSvgShape(
            content: svg,
            naturalSize: CGSize(width: 4000, height: 4000),
            customColor: .red,
            inRow: row.id
        )

        let shape = state.rows.first!.shapes.last!
        #expect(shape.type == .svg)
        #expect(shape.svgUseColor == true)
        #expect(max(shape.width, shape.height) <= row.svgMaxDimension + 0.5)
        #expect(state.selectedShapeIds == [shape.id])
    }
}
