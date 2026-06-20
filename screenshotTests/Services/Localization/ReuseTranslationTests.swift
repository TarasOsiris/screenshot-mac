import Testing
import Foundation
@testable import Screenshot_Bro

@MainActor
struct ReuseTranslationTests {

    private func shape(_ state: AppState, _ id: UUID) -> CanvasShapeModel? {
        state.rows.flatMap(\.shapes).first { $0.id == id }
    }

    /// A state with two "Get Started" text shapes in one row + a French locale (base = en).
    private func makeState() -> (AppState, URL, a: UUID, b: UUID) {
        let (state, dir) = makeTestState()
        let a = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Get Started")
        let b = CanvasShapeModel(type: .text, x: 0, y: 200, width: 300, height: 50, text: "Get Started")
        state.rows = [ScreenshotRow(label: "Hero", shapes: [a, b])]
        state.addLocale(LocaleDefinition(code: "fr", label: "French"))
        state.setActiveLocale("en")
        return (state, dir, a.id, b.id)
    }

    @Test func linkedShapeResolvesSharedTranslation() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.updateTranslationText(shapeId: a, localeCode: "fr", text: "Commencer")
        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)

        let resolvedB = LocaleService.resolveShape(shape(state, b)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedB.text == "Commencer")
        #expect(shape(state, b)?.translationKey != nil)
        #expect(shape(state, a)?.translationKey == shape(state, b)?.translationKey, "Both share one synthetic key")
    }

    @Test func editingTranslationOnOneMemberUpdatesAll() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.updateTranslationText(shapeId: b, localeCode: "fr", text: "Démarrer")

        let resolvedA = LocaleService.resolveShape(shape(state, a)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedA.text == "Démarrer")
    }

    @Test func editingBaseTextPropagatesToLinkedShapes() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.updateBaseText(shapeId: a, text: "Begin")

        #expect(shape(state, b)?.text == "Begin")
    }

    @Test func perShapeGeometryStaysIndependentWhenLinked() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        // Move B in the French locale; its offset must not leak onto A.
        var movedB = LocaleService.resolveShape(shape(state, b)!, localeCode: "fr", localeState: state.localeState)
        movedB.x += 40
        state.localeState.activeLocaleCode = "fr"
        state.rows[0].shapes[1] = LocaleService.splitUpdate(base: shape(state, b)!, updated: movedB, localeState: &state.localeState)

        let resolvedA = LocaleService.resolveShape(shape(state, a)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedA.x == 0, "A keeps its own position")
    }

    @Test func unlinkSnapshotsTranslationAndDecouples() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.updateTranslationText(shapeId: a, localeCode: "fr", text: "Commencer")
        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.unlinkTranslation(shapeId: b)

        #expect(shape(state, b)?.translationKey == nil)
        // B keeps a private copy of the shared translation...
        let resolvedB = LocaleService.resolveShape(shape(state, b)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedB.text == "Commencer")
        // ...and editing B no longer affects A.
        state.updateTranslationText(shapeId: b, localeCode: "fr", text: "Lancer")
        let resolvedA = LocaleService.resolveShape(shape(state, a)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedA.text == "Commencer")
    }

    @Test func catalogCollapsesReusedStringIntoOneEntry() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.updateTranslationText(shapeId: a, localeCode: "fr", text: "Commencer")
        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)

        let catalog = TranslationCatalog.build(rows: state.rows, localeState: state.localeState)
        #expect(catalog.strings.count == 1, "Two shapes sharing a string produce one entry")
        let entry = catalog.strings.values.first
        #expect(entry?.localizations["fr"]?.stringUnit.value == "Commencer")
    }

    @Test func inlineCanvasTranslationEditOnLinkedShapeIsShared() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.setActiveLocale("fr")
        // Editing the linked shape's translation on the canvas must reach the shared key, not vanish.
        state.commitInlineText(shapeId: b, text: "Salut", richText: nil, forLocaleCode: "fr")

        let resolvedA = LocaleService.resolveShape(shape(state, a)!, localeCode: "fr", localeState: state.localeState)
        #expect(resolvedA.text == "Salut")
    }

    @Test func inlineCanvasBaseEditOnLinkedShapePropagates() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.setActiveLocale("en")
        state.commitInlineText(shapeId: a, text: "Begin", richText: nil, forLocaleCode: "en")

        #expect(shape(state, b)?.text == "Begin")
    }

    @Test func setBaseLocalePreservesReusedTranslations() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.updateTranslationText(shapeId: a, localeCode: "fr", text: "Commencer")
        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        state.setBaseLocale("fr")

        // Both shapes' base text is now the French string...
        #expect(shape(state, a)?.text == "Commencer")
        #expect(shape(state, b)?.text == "Commencer")
        // ...and the old English is preserved as a shared translation for both members.
        let resolvedA = LocaleService.resolveShape(shape(state, a)!, localeCode: "en", localeState: state.localeState)
        let resolvedB = LocaleService.resolveShape(shape(state, b)!, localeCode: "en", localeState: state.localeState)
        #expect(resolvedA.text == "Get Started")
        #expect(resolvedB.text == "Get Started")
    }

    @Test func deletingAllMembersClearsSharedTranslation() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        state.updateTranslationText(shapeId: a, localeCode: "fr", text: "Commencer")
        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        let sharedKey = shape(state, a)!.textTranslationKey

        state.deleteShape(a)
        #expect(state.localeState.overrides["fr"]?[sharedKey] != nil, "Still referenced by B")
        state.deleteShape(b)
        #expect(state.localeState.overrides["fr"]?[sharedKey] == nil, "Orphaned shared translation is swept")
    }

    @Test func translationMatrixCollapsesReusedStringsToOneRow() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        #expect(state.textShapesForTranslationMatrix().count == 2, "Distinct strings → two rows")

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        let entries = state.textShapesForTranslationMatrix()
        #expect(entries.count == 1, "Reused string collapses to a single row")
        // The surviving row aggregates the rows that use the string (both shapes share row "Hero").
        #expect(entries.first?.rowLabel == "Hero")
    }

    @Test func reusableTargetsExcludeOwnString() {
        let (state, dir, a, b) = makeState()
        defer { cleanupTestState(dir) }

        // Before linking, A and B are distinct strings, so each sees the other as a target.
        #expect(state.reusableTranslationTargets(excludingShapeId: b).contains { $0.key == a.uuidString })

        state.linkTranslation(shapeId: b, toTargetKey: a.uuidString)
        // Once linked they share a key, so there's nothing else to reuse.
        #expect(state.reusableTranslationTargets(excludingShapeId: b).isEmpty)
    }
}
