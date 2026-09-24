import AppKit
@testable import Screenshot_Bro
import Testing

/// `selectedRowId` is read by the inspector, the properties bar and the macOS command menus, and
/// until 4.10 it was read by *every* editor row's body too — so an unguarded same-value write cost
/// as much as a real row change. `selectShape` must only write it when it actually changes.
///
/// This is pinned rather than left to review because `@Observable` notifies on same-value writes
/// silently: nothing about the call site looks wrong, and the cost only shows up in a profile.
@Suite(.serialized)
@MainActor
struct AppStateSelectionNotificationTests {

    /// True when `selectedRowId` was *notified*, whether or not its value changed — which is
    /// exactly the property under test.
    private func selectedRowIdDidNotify(_ state: AppState, during body: () -> Void) -> Bool {
        observationDidNotify({ state.selectedRowId }, during: body)
    }

    @Test func reselectingWithinTheSameRowDoesNotNotifySelectedRowId() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)

        state.addShape(CanvasShapeModel.defaultText(centerX: 100, centerY: 100))
        state.addShape(CanvasShapeModel.defaultText(centerX: 300, centerY: 300))
        let shapeIds = try #require(state.rows.first?.shapes.suffix(2).map(\.id))
        try #require(shapeIds.count == 2)
        state.selectShape(shapeIds[0], in: row.id)

        let notified = selectedRowIdDidNotify(state) {
            state.selectShape(shapeIds[1], in: row.id)
        }

        #expect(notified == false)
        #expect(state.selectedShapeIds == [shapeIds[1]])
    }

    @Test func selectingOnAnotherRowNotifiesSelectedRowId() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let firstRow = try #require(state.rows.first)

        state.addShape(CanvasShapeModel.defaultText(centerX: 100, centerY: 100))
        let firstShapeId = try #require(state.rows.first?.shapes.last?.id)
        state.selectShape(firstShapeId, in: firstRow.id)

        // `addRow` selects the row it adds, so put the selection back on the first row — otherwise
        // the tracked call below wouldn't be changing rows at all.
        state.addRow()
        let secondRow = try #require(state.rows.last)
        try #require(secondRow.id != firstRow.id)
        state.addShape(CanvasShapeModel.defaultText(centerX: 100, centerY: 100))
        let secondShapeId = try #require(state.rows.last?.shapes.last?.id)
        state.selectShape(firstShapeId, in: firstRow.id)
        try #require(state.selectedRowId == firstRow.id)

        let notified = selectedRowIdDidNotify(state) {
            state.selectShape(secondShapeId, in: secondRow.id)
        }

        #expect(notified)
        #expect(state.selectedRowId == secondRow.id)
        #expect(state.selectedShapeIds == [secondShapeId])
    }

    /// `selectRow`, `toggleShapeSelection` and `selectShapes` all clear this on a row change;
    /// `selectShape` used not to, so a shape added right after clicking into another row was
    /// centred using the previous row's scroll position (`AppState+Shapes.shapeCenter`).
    @Test func selectingOnAnotherRowClearsTheVisibleCanvasCenter() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let firstRow = try #require(state.rows.first)

        state.addRow()
        let secondRow = try #require(state.rows.last)
        state.addShape(CanvasShapeModel.defaultText(centerX: 100, centerY: 100))
        let shapeId = try #require(state.rows.last?.shapes.last?.id)

        state.selectRow(firstRow.id)
        state.visibleCanvasModelCenterX = 999
        state.selectShape(shapeId, in: secondRow.id)

        #expect(state.visibleCanvasModelCenterX == nil)
    }
}
