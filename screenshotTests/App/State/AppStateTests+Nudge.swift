import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    // MARK: - Nudge

    @Test func nudgeSelectedShapeMovesPosition() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.selectRow(state.rows.first!.id)
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 50, height: 50)
        state.addShape(shape)

        state.nudgeSelectedShapes(dx: 10, dy: -5)

        let updated = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(updated.x == 110)
        #expect(updated.y == 195)
    }

    @Test func discreteShapeUpdateFlushesPendingContinuousEdit() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first!.id)
        var shape = CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)
        shape.opacity = 0.8
        state.addShape(shape)

        var continuous = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        continuous.borderRadius = 40
        state.updateShapeContinuous(continuous)

        continuous.borderRadius = 120
        state.updateShapeContinuous(continuous)

        var discrete = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        discrete.opacity = 0.35
        state.updateShape(discrete)

        try await Task.sleep(for: .milliseconds(700))

        let updated = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(updated.borderRadius == 120)
        #expect(updated.opacity == 0.35)
        #expect(!state.edits.shapeEditThrottle.hasPending)
        #expect(state.continuousEditShapeId == nil)
    }

    @Test func selectionChangeFlushesPendingContinuousEdit() async throws {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.selectRow(state.rows.first!.id)
        let rect = CanvasShapeModel.defaultRectangle(centerX: 400, centerY: 700)
        let text = CanvasShapeModel.defaultText(centerX: 800, centerY: 700)
        state.addShape(rect)
        state.addShape(text)

        state.selectShape(rect.id, in: state.rows[0].id)

        var pendingRect = try #require(state.rows[0].shapes.first(where: { $0.id == rect.id }))
        pendingRect.borderRadius = 20
        state.updateShapeContinuous(pendingRect)

        pendingRect.borderRadius = 90
        state.updateShapeContinuous(pendingRect)

        state.selectShape(text.id, in: state.rows[0].id)
        try await Task.sleep(for: .milliseconds(700))

        let updatedRect = try #require(state.rows[0].shapes.first(where: { $0.id == rect.id }))
        #expect(updatedRect.borderRadius == 90)
        #expect(state.selectedShapeId == text.id)
        #expect(!state.edits.shapeEditThrottle.hasPending)
        #expect(state.continuousEditShapeId == nil)
    }
}
