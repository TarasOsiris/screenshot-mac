import Testing
import Foundation
@testable import Screenshot_Bro

/// Covers the off-main debounced autosave path (`saveAllAsync` + save queue).
@MainActor
struct AutosaveAsyncTests {

    /// Standard fixture: seeded state with one text shape added to the first row.
    private func makeStateWithTextShape() throws -> (state: AppState, tempDir: URL, projectId: UUID, shape: CanvasShapeModel) {
        let (state, tempDir) = makeTestState()
        let projectId = try #require(state.activeProjectId)
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shape = try #require(state.rows.first?.shapes.first)
        return (state, tempDir, projectId, shape)
    }
    @Test func asyncAutosavePersistsLatestRows() throws {
        let (state, tempDir, projectId, _) = try makeStateWithTextShape()
        defer { cleanupTestState(tempDir) }
        let expectedShapeCount = try #require(state.rows.first?.shapes.count)

        state.saveAllAsync()
        AppState.saveQueue.sync {}

        let saved = try #require(PersistenceService.loadProject(projectId))
        #expect(saved.rows.first?.shapes.count == expectedShapeCount)
    }

    @Test func rapidSuccessiveSavesLastStateWins() throws {
        var (state, tempDir, projectId, shape) = try makeStateWithTextShape()
        defer { cleanupTestState(tempDir) }

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
        let (state, tempDir, projectId, _) = try makeStateWithTextShape()
        defer { cleanupTestState(tempDir) }
        let expectedShapeCount = try #require(state.rows.first?.shapes.count)

        state.saveAllAsync()
        state.flushPendingSavesSynchronously()

        let saved = try #require(PersistenceService.loadProject(projectId))
        #expect(saved.rows.first?.shapes.count == expectedShapeCount)
    }

    /// An edit schedules a debounced save; flushing before the debounce fires
    /// must still persist the edit synchronously.
    @Test func flushAfterEditPersistsImmediately() throws {
        var (state, tempDir, projectId, shape) = try makeStateWithTextShape()
        defer { cleanupTestState(tempDir) }
        shape.x = 333
        state.updateShape(shape)

        state.flushPendingSavesSynchronously()

        let saved = try #require(PersistenceService.loadProject(projectId))
        let savedShape = try #require(saved.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(savedShape.x == 333)
    }
}
