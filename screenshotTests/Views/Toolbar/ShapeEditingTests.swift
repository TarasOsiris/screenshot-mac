import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// The shared editing layer both the properties bar and the selection inspector call. These pin
/// the behaviours a second caller could otherwise quietly break.
@Suite(.serialized)
@MainActor
struct ShapeEditingTests {
    private struct Editor: ShapeEditing {
        let state: AppState
    }

    private final class DraftBox {
        var text = ""
        var isActive = false
        var draft: ShapeFieldDraft {
            ShapeFieldDraft(
                text: Binding(get: { self.text }, set: { self.text = $0 }),
                isActive: Binding(get: { self.isActive }, set: { self.isActive = $0 })
            )
        }
    }

    private func makeEditor(adding shape: CanvasShapeModel) -> (AppState, URL, Editor, UndoManager) {
        let (state, tempDir) = makeTestState()
        state.selectRow(state.rows.first!.id)
        state.addShape(shape)
        let undoManager = state.undoManager!
        undoManager.removeAllActions()
        return (state, tempDir, Editor(state: state), undoManager)
    }

    private func documentShape(_ state: AppState, _ id: UUID) -> CanvasShapeModel? {
        state.rows.first?.shapes.first { $0.id == id }
    }

    @Test func discreteBindingIsOneUndoStep() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, undoManager) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        editor.shapeBinding(shape.id, \.opacity).wrappedValue = 0.25

        #expect(documentShape(state, shape.id)?.opacity == 0.25)
        #expect(undoManager.canUndo)
        undoManager.undo()
        #expect(documentShape(state, shape.id)?.opacity == 1)
        #expect(!undoManager.canUndo)
    }

    @Test func continuousBindingComposesOffDocumentUntilItSettles() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        editor.shapeBinding(shape.id, \.rotation, continuous: true).wrappedValue = 30

        #expect(documentShape(state, shape.id)?.rotation == 0, "A burst must leave the document alone")
        #expect(editor.editingShape(shape.id)?.rotation == 30, "Controls read the in-flight value")
        #expect(editor.documentShape(at: 0, shapeIdx: 0).rotation == 0)

        state.finishContinuousEditIfNeeded()
        #expect(documentShape(state, shape.id)?.rotation == 30)
    }

    /// The inspector's container body reads `documentShape`; a slider tick must not invalidate it.
    @Test func documentShapeIsNotNotifiedByABurst() {
        var shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        shape.rotation = 45
        let notified = observationDidNotify({ editor.documentShape(at: 0, shapeIdx: 0) }) {
            state.updateShapeContinuous(shape)
        }
        #expect(!notified)
        state.finishContinuousEditIfNeeded()
    }

    /// Pickers and toggles sit next to sliders in the inspector; a drag must not re-render them.
    @Test func aNonContinuousBindingIsNotNotifiedByABurst() {
        var shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        shape.rotation = 45
        let toggleNotified = observationDidNotify({ editor.shapeBinding(shape.id, \.clipToTemplate, default: false).wrappedValue }) {
            state.updateShapeContinuous(shape)
        }
        #expect(!toggleNotified)
        #expect(editor.shapeBinding(shape.id, \.rotation, continuous: true).wrappedValue == 45, "The dragged control still sees the burst")
        state.finishContinuousEditIfNeeded()
    }

    /// A field flushing its draft after the selection moved to another row must still find its shape.
    @Test func lookupFindsAShapeOutsideTheSelectedRow() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        state.addRow()
        #expect(state.selectedRowId != state.rows.first?.id)
        editor.shapeBinding(shape.id, \.opacity).wrappedValue = 0.5
        #expect(documentShape(state, shape.id)?.opacity == 0.5)
    }

    @Test func enablingOutlineWritesColorAndWidthTogether() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        editor.outlineEnabledBinding(shape.id).wrappedValue = true
        #expect(documentShape(state, shape.id)?.outlineWidth == CanvasShapeModel.defaultOutlineWidth)
        #expect(documentShape(state, shape.id)?.outlineColorData != nil)

        editor.outlineEnabledBinding(shape.id).wrappedValue = false
        #expect(documentShape(state, shape.id)?.outlineWidth == nil)
        #expect(documentShape(state, shape.id)?.outlineColorData == nil)
    }

    /// X is shown and typed relative to the template the shape sits in, not the whole row strip.
    @Test func geometryXIsRelativeToTheOwningTemplate() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = state.rows.first!
        state.selectRow(row.id)
        let shape = CanvasShapeModel(type: .rectangle, x: row.templateWidth + 100, y: 100, width: 50, height: 50)
        state.addShape(shape)
        let editor = Editor(state: state)

        #expect(editor.currentGeometryString(.x, for: shape.id) == "100")

        let boxes = Dictionary(uniqueKeysWithValues: ShapeGeometryAxis.allCases.map { ($0, DraftBox()) })
        boxes[.x]!.text = "200"
        boxes[.x]!.isActive = true
        editor.commitGeometry(.x, to: shape.id) { boxes[$0]!.draft }

        #expect(documentShape(state, shape.id)?.x == row.templateWidth + 200)
        #expect(boxes[.x]!.isActive == false)
        #expect(boxes[.width]!.text == "50", "Every commit re-reads all four fields")
    }

    /// Reprogramming the field to the size it already has must not write — that write would
    /// flatten a rich-text run's mixed sizes.
    @Test func noOpFontSizeKeystrokeWritesNothing() {
        var shape = CanvasShapeModel.defaultText(centerX: 300, centerY: 300)
        shape.fontSize = 48
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        let box = DraftBox()
        box.text = "48"
        editor.applyFontSizeContinuously(fallbackShapeId: shape.id, draft: box.draft)

        #expect(state.liveShapeEdit.liveShape(for: shape.id) == nil)
        #expect(!state.edits.shapeEditThrottle.hasPending)
    }

    /// A canvas drag reaches `rows` only on mouse-up, so the readouts follow the gesture through
    /// `liveShapeGeometry` — including X's rebase when the shape crosses into another template.
    @Test func canvasGestureMovesTheReadoutsWithoutTouchingTheDocument() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        let templateWidth = state.rows.first!.templateWidth
        state.liveShapeGeometry.update(
            .init(x: templateWidth + 30, y: 220, width: 80, height: 90, rotation: 45),
            for: shape.id
        )

        #expect(editor.currentGeometryString(.x, for: shape.id) == "30", "X rebases to the new template")
        #expect(editor.currentGeometryString(.y, for: shape.id) == "220")
        #expect(editor.currentGeometryString(.width, for: shape.id) == "80")
        #expect(editor.currentGeometryString(.height, for: shape.id) == "90")
        #expect(editor.currentRotationString(for: shape.id) == "45")
        #expect(editor.rotationBinding(shape.id).wrappedValue == 45, "The slider follows the handle")
        #expect(documentShape(state, shape.id)?.x == 100, "The gesture has not landed yet")

        state.liveShapeGeometry.end()
        #expect(editor.currentGeometryString(.x, for: shape.id) == "100")
        #expect(editor.currentRotationString(for: shape.id) == "0")
    }

    /// The readout is keyed by shape: a drag elsewhere must not move this one's fields.
    @Test func anotherShapesGestureLeavesTheReadoutsAlone() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        state.liveShapeGeometry.update(.init(x: 999, y: 999, width: 999, height: 999, rotation: 99), for: UUID())

        #expect(editor.currentGeometryString(.x, for: shape.id) == "100")
        #expect(editor.liveGeometryShape(shape.id)?.rotation == 0)
    }

    /// The readout is display-only. If it ever leaked into `editingShape`, every write site in
    /// the bar and the inspector would become a way to persist a frame the pointer is still
    /// moving — reachable on iPad, where the bar is on screen during a canvas drag.
    @Test func aLiveGeometryFrameNeverReachesAWrite() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, _) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        state.liveShapeGeometry.update(.init(x: 400, y: 400, width: 200, height: 200, rotation: 45), for: shape.id)

        editor.shapeBinding(shape.id, \.opacity).wrappedValue = 0.5
        editor.outlineEnabledBinding(shape.id).wrappedValue = true
        let box = DraftBox()
        box.text = "50"
        box.isActive = true
        editor.commitOpacity(to: shape.id, draft: box.draft)

        let written = documentShape(state, shape.id)
        #expect(written?.opacity == 0.5, "The write itself still lands")
        #expect(written?.x == 100)
        #expect(written?.y == 100)
        #expect(written?.width == 50)
        #expect(written?.height == 50)
        #expect(written?.rotation == 0)
    }

    @Test func badOpacityInputRestoresTheDisplay() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let (state, tempDir, editor, undoManager) = makeEditor(adding: shape)
        defer { cleanupTestState(tempDir) }

        let box = DraftBox()
        box.text = "abc"
        box.isActive = true
        editor.commitOpacity(to: shape.id, draft: box.draft)

        #expect(box.text == "100")
        #expect(!box.isActive)
        #expect(!undoManager.canUndo)
        #expect(documentShape(state, shape.id)?.opacity == 1)
    }
}
