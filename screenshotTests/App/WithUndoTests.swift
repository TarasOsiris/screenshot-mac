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

    @Test func documentUndoFlushesPendingContinuousEditImmediately() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.fontSize = 48
        state.addShape(shape)
        um.removeAllActions()

        var updated = state.rows.first!.shapes.first { $0.id == shape.id }!
        updated.fontSize = 96
        state.updateShapeContinuous(updated)

        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontSize == 96)
        #expect(!um.canUndo, "The debounced continuous edit has not registered yet")
        #expect(state.canUndoDocumentAction, "Document undo must be enabled while a continuous edit is pending")

        state.undoDocumentAction()

        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontSize == 48)
        #expect(!state.canUndoDocumentAction, "The immediate undo consumed the flushed continuous edit")
    }

    @Test func redoIsUnavailableWhileContinuousEditPending() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.fontSize = 48
        state.addShape(shape)
        um.removeAllActions()

        // A discrete edit then undo leaves a redoable action on the stack.
        var edited = state.rows.first!.shapes.first { $0.id == shape.id }!
        edited.fontSize = 72
        state.updateShape(edited)
        state.undoDocumentAction()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontSize == 48)
        #expect(state.canRedoDocumentAction, "Redo of the discrete edit is available")

        // Start a continuous edit (debounced — not yet registered).
        var dragged = state.rows.first!.shapes.first { $0.id == shape.id }!
        dragged.fontSize = 96
        state.updateShapeContinuous(dragged)

        #expect(!state.canRedoDocumentAction, "Redo must be disabled while a continuous edit is pending")

        // Invoking redo commits the pending edit instead of silently discarding it; redo is a no-op.
        state.redoDocumentAction()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontSize == 96, "Pending continuous edit was committed")
    }

    /// A continuous (row-scoped) edit must survive repeated undo↔redo cycling — the earlier
    /// two-closure registration dropped the step after the first redo.
    @Test func continuousEditRedoRemainsUndoable() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        state.addShape(shape)
        um.removeAllActions()
        let baseX = state.rows.first!.shapes.first { $0.id == shape.id }!.x

        shape.x = 99
        state.updateShapeContinuous(shape)
        state.finishContinuousEditIfNeeded()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == 99)

        for cycle in 0..<3 {
            state.undoDocumentAction()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX, "undo -> base (cycle \(cycle))")
            #expect(state.canRedoDocumentAction, "redo available after undo (cycle \(cycle))")

            state.redoDocumentAction()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == 99, "redo -> edited (cycle \(cycle))")
            #expect(state.canUndoDocumentAction, "step still undoable after redo (cycle \(cycle))")
        }
    }

    /// A pending arrow-key nudge interleaved with a discrete action must register in
    /// chronological order, so neither edit clobbers the other on undo.
    @Test func nudgeInterleavedWithDiscreteActionKeepsOrder() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let moved = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.addShape(moved)
        state.selectedShapeIds = [moved.id]
        um.removeAllActions()
        let baseX = state.rows.first!.shapes.first { $0.id == moved.id }!.x

        // Nudge captures a base + schedules a debounced registration (not yet fired).
        state.nudgeSelectedShapes(dx: 5, dy: 0)
        #expect(!um.canUndo, "Nudge has not registered its debounced step yet")

        // A discrete action lands inside the debounce window — it must flush the nudge first.
        let added = CanvasShapeModel(type: .circle, x: 100, y: 100, width: 20, height: 20)
        state.addShape(added)

        func has(_ id: UUID) -> Bool { state.rows.first!.shapes.contains { $0.id == id } }
        func x(_ id: UUID) -> CGFloat { state.rows.first!.shapes.first { $0.id == id }!.x }
        #expect(x(moved.id) == baseX + 5)
        #expect(has(added.id))

        state.undoDocumentAction()  // undo the discrete add
        #expect(!has(added.id), "Newest action (add) undoes first")
        #expect(x(moved.id) == baseX + 5, "Nudge is untouched by undoing the later add")

        state.undoDocumentAction()  // undo the nudge
        #expect(x(moved.id) == baseX, "Nudge reverts on the second undo")
        #expect(has(moved.id), "Undoing the nudge must not drop the moved shape")
    }

    /// The nudge finisher routes through the same row-scoped recursive registration, so it
    /// too must survive repeated undo↔redo cycling.
    @Test func nudgeRedoRemainsUndoable() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.addShape(shape)
        state.selectedShapeIds = [shape.id]
        um.removeAllActions()
        let baseX = state.rows.first!.shapes.first { $0.id == shape.id }!.x

        state.nudgeSelectedShapes(dx: 7, dy: 0)
        state.finishNudgeIfNeeded()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX + 7)

        for cycle in 0..<3 {
            state.undoDocumentAction()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX, "undo -> base (cycle \(cycle))")
            state.redoDocumentAction()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX + 7, "redo -> moved (cycle \(cycle))")
            #expect(state.canUndoDocumentAction, "still undoable after redo (cycle \(cycle))")
        }
    }

    @Test func systemFontFamilyUndoRedoCycles() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        state.addShape(shape)
        um.removeAllActions()

        var updated = state.rows.first!.shapes.first { $0.id == shape.id }!
        updated.fontName = "Helvetica"
        RichTextUtils.syncShapeStyleIfNeeded(in: &updated, property: .fontName)
        state.updateShape(updated)

        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontName == "Helvetica")

        state.undoDocumentAction()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontName == nil)

        state.redoDocumentAction()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.fontName == "Helvetica")
    }

    @Test func importedFontSelectionUndoesAsOneStep() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.fontName = "System"
        shape.fontWeight = 400
        shape.italic = false
        state.addShape(shape)
        um.removeAllActions()

        let imported = ImportedCustomFontSelection(
            fontName: "Family Bold Italic",
            fontWeight: 700,
            italic: true
        )
        var updated = state.rows.first!.shapes.first { $0.id == shape.id }!
        RichTextUtils.applyImportedFontSelection(imported, to: &updated, property: .fontName)
        state.updateShape(updated)

        let applied = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(applied.fontName == "Family Bold Italic")
        #expect(applied.fontWeight == 700)
        #expect(applied.italic == true)

        state.undoDocumentAction()
        let reverted = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(reverted.fontName == "System")
        #expect(reverted.fontWeight == 400)
        #expect(reverted.italic == false)
        #expect(!um.canUndo, "Imported font selection should be one undo step")

        state.redoDocumentAction()
        let redone = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(redone.fontName == "Family Bold Italic")
        #expect(redone.fontWeight == 700)
        #expect(redone.italic == true)
    }

    // MARK: - Row-scoped undo (withRowUndo)

    /// Deleting a shape removes its locale overrides; the row-scoped undo step
    /// must restore both the shape and the overrides (full localeState capture).
    @Test func deleteShapeUndoRestoresLocaleOverrides() throws {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        state.addShape(shape)
        state.addLocale(.init(code: "fr", label: "French"))
        var translated = LocaleService.resolveShape(
            state.rows.first!.shapes.first { $0.id == shape.id }!,
            localeState: state.localeState
        )
        translated.text = "Bonjour"
        state.updateShape(translated)
        let overrideKey = shape.textTranslationKey
        #expect(state.localeState.overrides["fr"]?[overrideKey]?.text == "Bonjour")
        um.removeAllActions()

        state.deleteShape(shape.id)
        #expect(!state.rows.first!.shapes.contains { $0.id == shape.id })
        #expect(state.localeState.overrides["fr"]?[overrideKey] == nil, "Delete drops the override")

        um.undo()
        #expect(state.rows.first!.shapes.contains { $0.id == shape.id }, "Undo restores the shape")
        #expect(state.localeState.overrides["fr"]?[overrideKey]?.text == "Bonjour", "Undo restores the locale override")

        um.redo()
        #expect(!state.rows.first!.shapes.contains { $0.id == shape.id })
        #expect(state.localeState.overrides["fr"]?[overrideKey] == nil)
    }

    /// Duplicating a shape copies its locale overrides to the new id; undo must
    /// remove both the copy and its copied overrides.
    @Test func duplicateUndoRemovesCopiedOverrides() throws {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        state.addShape(shape)
        state.addLocale(.init(code: "fr", label: "French"))
        var translated = LocaleService.resolveShape(
            state.rows.first!.shapes.first { $0.id == shape.id }!,
            localeState: state.localeState
        )
        translated.text = "Bonjour"
        state.updateShape(translated)
        um.removeAllActions()

        state.selectShape(shape.id, in: rowId)
        let copyId = try #require(state.insertDuplicate(of: shape.id, offsetX: 10, offsetY: 10, undoName: "Duplicate Shape"))
        #expect(state.localeState.overrides["fr"]?[copyId.uuidString]?.text == "Bonjour", "Duplicate copies the override")

        um.undo()
        #expect(!state.rows.first!.shapes.contains { $0.id == copyId }, "Undo removes the copy")
        #expect(state.localeState.overrides["fr"]?[copyId.uuidString] == nil, "Undo removes the copied override")

        um.redo()
        #expect(state.rows.first!.shapes.contains { $0.id == copyId })
        #expect(state.localeState.overrides["fr"]?[copyId.uuidString]?.text == "Bonjour")
    }

    /// Row-scoped steps re-register their inverse recursively, so a converted op
    /// must survive repeated undo↔redo cycling like the whole-document path.
    @Test func rowScopedUndoRedoCyclesRepeatedly() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.addShape(shape)
        state.selectedShapeIds = [shape.id]
        um.removeAllActions()
        let baseX = state.rows.first!.shapes.first { $0.id == shape.id }!.x

        state.applyGroupDrag(offset: CGSize(width: 25, height: 0))
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX + 25)

        for cycle in 0..<3 {
            um.undo()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX, "undo -> base (cycle \(cycle))")
            um.redo()
            #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.x == baseX + 25, "redo -> moved (cycle \(cycle))")
            #expect(um.canUndo, "still undoable after redo (cycle \(cycle))")
        }
    }

    /// A row-scoped op invoked inside `withUndo` joins the outer transaction —
    /// exactly one (whole-document) step is registered.
    @Test func rowUndoNestedInWithUndoRegistersOneStep() {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.withUndo("Outer") {
            state.addShape(shape)  // addShape's withRowUndo must join, not double-register
        }
        #expect(state.rows.first!.shapes.contains { $0.id == shape.id })

        um.undo()
        #expect(!state.rows.first!.shapes.contains { $0.id == shape.id }, "One undo reverts the nested op")
        #expect(!um.canUndo, "Nested row-scoped op must not register a second step")
    }

    /// The inverse nesting: `withUndo` inside `withRowUndo` also joins, leaving
    /// a single row-scoped step.
    @Test func withUndoNestedInRowUndoRegistersOneStep() throws {
        let (state, tempDir, um) = makeUndoState()
        defer { cleanup(tempDir) }
        let rowId = state.rows.first!.id
        state.selectRow(rowId)

        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 20, height: 20)
        state.addShape(shape)
        um.removeAllActions()

        state.withRowUndo("Outer", rowId: rowId) {
            state.updateShapes([shape.id], in: rowId, undoName: "Inner") { $0.opacity = 0.5 }
        }
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.opacity == 0.5)

        um.undo()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.opacity == 1.0, "One undo reverts the nested edit")
        #expect(!um.canUndo, "Nested withUndo must not register a second step")
    }
}
