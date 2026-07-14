import Testing
import Foundation
@testable import Screenshot_Bro

/// Covers the off-main debounced autosave path (`saveAllAsync` + save queue).
@MainActor
struct AutosaveAsyncTests {
    @Test func asyncAutosavePersistsLatestRows() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let expectedShapeCount = try #require(state.rows.first?.shapes.count)

        state.saveAllAsync()
        AppState.saveQueue.sync {}

        let saved = try #require(PersistenceService.loadProject(projectId))
        #expect(saved.rows.first?.shapes.count == expectedShapeCount)
    }

    @Test func rapidSuccessiveSavesLastStateWins() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        var shape = try #require(state.rows.first?.shapes.first)

        shape.x = 111
        state.updateShape(shape)
        state.saveAllAsync()
        shape.x = 222
        state.updateShape(shape)
        state.saveAllAsync()
        AppState.saveQueue.sync {}

        let saved = try #require(PersistenceService.loadProject(projectId))
        let savedShape = try #require(saved.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(savedShape.x == 222)
    }

    /// The quit flush must drain an in-flight queued write before returning, so
    /// nothing is lost even when the process exits right after.
    @Test func flushDrainsInFlightAsyncWrite() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let expectedShapeCount = try #require(state.rows.first?.shapes.count)

        state.saveAllAsync()
        state.flushPendingSavesSynchronously()

        let saved = try #require(PersistenceService.loadProject(projectId))
        #expect(saved.rows.first?.shapes.count == expectedShapeCount)
    }

    /// An edit schedules a debounced save; flushing before the debounce fires
    /// must still persist the edit synchronously.
    @Test func flushAfterEditPersistsImmediately() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let projectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        var shape = try #require(state.rows.first?.shapes.first)
        shape.x = 333
        state.updateShape(shape)

        state.flushPendingSavesSynchronously()

        let saved = try #require(PersistenceService.loadProject(projectId))
        let savedShape = try #require(saved.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(savedShape.x == 333)
    }
}
