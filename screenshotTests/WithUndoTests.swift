import Testing
import AppKit
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct WithUndoTests {

    /// `withUndo` only records a step when an `UndoManager` is attached. `groupsByEvent = false`
    /// makes each registration independently undoable without spinning a run loop.
    private func makeUndoState() -> (AppState, URL, UndoManager) {
        let (state, tempDir) = makeTestState()
        let um = UndoManager()
        um.groupsByEvent = false
        state.undoManager = um
        return (state, tempDir, um)
    }
    private func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }

    @Test func discreteEditUndoRedoCycles() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.addShape(shape)
        #expect(state.rows.first!.shapes.contains { $0.id == shape.id })
        #expect(um.canUndo)

        um.undo()
        #expect(!state.rows.first!.shapes.contains { $0.id == shape.id }, "Undo removes the added shape")

        um.redo()
        #expect(state.rows.first!.shapes.contains { $0.id == shape.id }, "Redo re-adds the shape")
    }

    @Test func noOpEditRegistersNoUndoStep() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        // No shape ids match → body mutates nothing → no step should be pushed.
        state.updateShapes([], in: rowId, undoName: "Edit Shapes") { $0.opacity = 0.1 }
        #expect(!um.canUndo, "A no-op edit must not push an undo step")
    }

    @Test func localeStateChangeUndoesAndRedoes() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let before = state.localeState.locales.count

        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.localeState.locales.count == before + 1)
        #expect(state.localeState.activeLocaleCode == "fr")

        um.undo()
        #expect(state.localeState.locales.count == before, "Undo restores the locale list")
        #expect(state.localeState.activeLocaleCode != "fr", "Undo restores the active locale")

        um.redo()
        #expect(state.localeState.locales.count == before + 1, "Redo re-adds the locale")
    }

    @Test func replacingScreenshotWithSameDimensionsIsUndoable() throws {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let shapeId = try #require(state.rows.first?.shapes.first { $0.type == .device }?.id)
        let projectId = try #require(state.activeProjectId)
        let resourcesDir = PersistenceService.resourcesDir(projectId)

        state.saveImage(makeSolidImage(.systemRed, width: 1206, height: 2622), for: shapeId)
        let firstFile = try #require(state.rows.first?.shapes.first { $0.id == shapeId }?.displayImageFileName)
        #expect(FileManager.default.fileExists(atPath: resourcesDir.appendingPathComponent(firstFile).path))

        um.removeAllActions()
        state.saveImage(makeSolidImage(.systemGreen, width: 1206, height: 2622), for: shapeId)
        let secondFile = try #require(state.rows.first?.shapes.first { $0.id == shapeId }?.displayImageFileName)

        #expect(secondFile != firstFile, "Replacing image bytes should produce a model-visible resource reference")
        #expect(um.canUndo, "Same-dimension replacement still needs an undo step")
        #expect(FileManager.default.fileExists(atPath: resourcesDir.appendingPathComponent(firstFile).path))
        #expect(FileManager.default.fileExists(atPath: resourcesDir.appendingPathComponent(secondFile).path))

        um.undo()
        #expect(state.rows.first?.shapes.first { $0.id == shapeId }?.displayImageFileName == firstFile)
        #expect(state.screenshotImages[firstFile] != nil)

        um.redo()
        #expect(state.rows.first?.shapes.first { $0.id == shapeId }?.displayImageFileName == secondFile)
        #expect(state.screenshotImages[secondFile] != nil)
    }

    @Test func continuousEditCollapsesToOneUndoStep() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        state.addShape(shape)
        um.removeAllActions()  // isolate the continuous burst from the add step
        let baseX = state.rows.first!.shapes.first { $0.id == shape.id }!.x

        shape.x = 30; state.updateShapeContinuous(shape)
        shape.x = 60; state.updateShapeContinuous(shape)
        state.finishContinuousEditIfNeeded()

        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == 60)
        #expect(um.canUndo)

        um.undo()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX, "Whole burst reverts at once")
        #expect(!um.canUndo, "A continuous burst is a single undo step")
    }
}
