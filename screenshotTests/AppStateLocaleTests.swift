import Testing
import AppKit
@testable import Screenshot_Bro

@Suite(.serialized)
@MainActor
struct AppStateLocaleTests {

    @Test func portuguesePresetsIncludeBrazilAndPortugal() {
        #expect(LocalePresets.all.contains(.init(code: "pt-BR", label: "Portuguese (Brazil)")))
        #expect(LocalePresets.all.contains(.init(code: "pt-PT", label: "Portuguese (Portugal)")))
    }

    @Test func legacyPortugueseLocaleKeepsBrazilFlag() {
        let legacy = LocaleDefinition(code: "pt", label: "Portuguese")

        #expect(legacy.flagLabel == "🇧🇷 Portuguese")
    }

    @Test func resetTranslationRemovesOverrideFromProgress() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shapeId = try #require(state.rows.first?.shapes.first(where: { $0.type == .text })?.id)

        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.translationProgress() == (0, 1))

        state.updateTranslationText(shapeId: shapeId, text: "Bonjour")
        #expect(state.translationProgress() == (1, 1))

        state.resetTranslationText(shapeId: shapeId)
        #expect(state.translationProgress() == (0, 1))
    }

    /// Regression: editing a text shape in a non-base locale and switching back to the
    /// base locale without first deselecting must commit the typed text to the *editing*
    /// locale's override — never overwrite the base text. (Repro: highlight text in German,
    /// switch to English, and English was clobbered with the German text.)
    @Test func switchingLocaleMidEditCommitsToEditingLocale() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let baseShape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))
        let shapeId = baseShape.id
        let baseText = baseShape.text

        state.addLocale(.init(code: "de", label: "German"))
        state.setActiveLocale("de")

        // Mimic the inline editor: it captures the locale-resolved shape and, on commit,
        // writes the typed text back through updateShape under whatever locale is active.
        let resolved = LocaleService.resolveShape(baseShape, localeState: state.localeState)
        state.isEditingText = true
        state.registerInlineTextCommit(for: shapeId) {
            var updated = resolved
            updated.text = "Hallo"
            updated.richText = nil
            state.updateShape(updated)
        }

        // Switch back to base *without* a prior commit — this must flush the edit to German first.
        state.setActiveLocale("en")

        let committedBase = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId }))
        #expect(committedBase.text == baseText)
        #expect(state.localeState.override(forCode: "de", shapeId: shapeId)?.text == "Hallo")
        #expect(state.localeState.activeLocaleCode == "en")
    }

    /// The inline-commit registration is keyed by shape, so a late teardown from a
    /// previously-editing shape must not clear a newer editor's handler (otherwise a
    /// subsequent locale switch wouldn't flush the new editor and its text would leak
    /// to the wrong locale).
    @Test func laterEditorRegistrationSurvivesStaleClear() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let shapeA = UUID()
        let shapeB = UUID()
        var committed: UUID?
        var ended: UUID?

        state.registerInlineTextCommit(for: shapeA, endEditing: { ended = shapeA }) { committed = shapeA }
        state.registerInlineTextCommit(for: shapeB, endEditing: { ended = shapeB }) { committed = shapeB }
        state.clearInlineTextCommit(for: shapeA) // stale teardown from the shape we left

        #expect(state.commitActiveInlineTextEdit != nil)
        state.commitAllPendingEdits()
        #expect(committed == shapeB)
        #expect(ended == shapeB)
        #expect(state.commitActiveInlineTextEdit == nil)
    }

    @Test func forcedPendingEditFlushEndsActiveInlineEditor() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let shapeId = UUID()
        var didCommit = false
        var didEnd = false

        state.isEditingText = true
        state.registerInlineTextCommit(for: shapeId, endEditing: {
            didEnd = true
            state.isEditingText = false
        }) {
            didCommit = true
        }

        state.commitAllPendingEdits()

        #expect(didCommit)
        #expect(didEnd)
        #expect(state.isEditingText == false)
        #expect(state.commitActiveInlineTextEdit == nil)
    }

    @Test func synchronousSaveFlushCommitsActiveInlineTextEdit() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))
        let projectId = try #require(state.activeProjectId)

        state.isEditingText = true
        state.registerInlineTextCommit(for: shape.id) {
            var updated = shape
            updated.text = "Edited before quit"
            state.updateShape(updated)
        }

        state.flushPendingSavesSynchronously()

        let liveShape = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(liveShape.text == "Edited before quit")

        let saved = try #require(PersistenceService.loadProject(projectId))
        let savedShape = try #require(saved.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(savedShape.text == "Edited before quit")
    }

    @Test func routineAutosaveDoesNotCommitActiveInlineTextEdit() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))
        var didCommit = false

        state.isEditingText = true
        state.registerInlineTextCommit(for: shape.id) {
            didCommit = true
            var updated = shape
            updated.text = "Still typing"
            state.updateShape(updated)
        }

        state.saveAll()

        let liveShape = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(liveShape.text == shape.text)
        #expect(didCommit == false)
        #expect(state.commitActiveInlineTextEdit != nil)
    }

    /// commitInlineText applies only the text onto the *live* base shape, so a concurrent edit
    /// made while the editor was open (here, a move) isn't reverted by a stale captured model.
    @Test func commitInlineTextPreservesConcurrentGeometryChange() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        var shape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))
        let shapeId = shape.id

        shape.x += 123
        shape.y += 45
        state.updateShape(shape)
        let movedX = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId })?.x)
        let movedY = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId })?.y)

        state.commitInlineText(shapeId: shapeId, text: "Committed", richText: nil, forLocaleCode: state.localeState.baseLocaleCode)

        let live = try #require(state.rows.first?.shapes.first(where: { $0.id == shapeId }))
        #expect(live.text == "Committed")
        #expect(live.x == movedX)
        #expect(live.y == movedY)
    }

    /// commitInlineText writes to the locale it was given, not the active one — so an edit flushed
    /// after the active locale already changed still lands in the locale it was typed in.
    @Test func commitInlineTextWritesToSpecifiedLocaleNotActive() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let row = try #require(state.rows.first)
        state.addShape(
            CanvasShapeModel.defaultText(
                centerX: row.templateWidth / 2,
                centerY: row.templateHeight / 2
            )
        )
        let shape = try #require(state.rows.first?.shapes.first(where: { $0.type == .text }))
        let baseText = shape.text

        state.addLocale(.init(code: "de", label: "German"))
        // Force the active locale back to base; the commit must still target "de" explicitly.
        state.setActiveLocale(state.localeState.baseLocaleCode)
        #expect(state.localeState.activeLocaleCode == state.localeState.baseLocaleCode)
        state.commitInlineText(shapeId: shape.id, text: "Hallo", richText: nil, forLocaleCode: "de")

        let live = try #require(state.rows.first?.shapes.first(where: { $0.id == shape.id }))
        #expect(live.text == baseText)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == "Hallo")
    }

    /// Resetting the shared `isEditingText` flag (a previous editor's teardown) must not clear a
    /// newer editor's registration — only the keyed clear for the shape that left should fire.
    @Test func editingFlagResetDoesNotClearNewerEditorRegistration() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let shapeA = UUID()
        let shapeB = UUID()
        var committed: UUID?
        var ended: UUID?

        state.isEditingText = true
        state.registerInlineTextCommit(for: shapeA, endEditing: { ended = shapeA }) { committed = shapeA }
        state.registerInlineTextCommit(for: shapeB, endEditing: { ended = shapeB }) { committed = shapeB }

        // Shape A tears down: shared flag flips false, then a keyed clear for A only.
        state.isEditingText = false
        state.clearInlineTextCommit(for: shapeA)

        #expect(state.commitActiveInlineTextEdit != nil)
        state.commitAllPendingEdits()
        #expect(committed == shapeB)
        #expect(ended == shapeB)
    }

}
