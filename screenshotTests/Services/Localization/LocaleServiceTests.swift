import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

struct LocaleServiceTests {

    // MARK: - resolveShape

    @Test func resolveShapeReturnsUnchangedForBaseLocale() {
        let shape = CanvasShapeModel(type: .text, x: 100, y: 200, width: 300, height: 50, text: "Hello")
        let state = LocaleState.default // en is base, active is en
        let resolved = LocaleService.resolveShape(shape, localeState: state)
        #expect(resolved.x == 100)
        #expect(resolved.y == 200)
        #expect(resolved.text == "Hello")
    }

    @Test func resolveShapeAppliesPositionOffsets() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(offsetX: 10, offsetY: -20, offsetWidth: 50, offsetHeight: 30)]]
        )
        let resolved = LocaleService.resolveShape(shape, localeState: state)
        #expect(resolved.x == 110)
        #expect(resolved.y == 180)
        #expect(resolved.width == 350)
        #expect(resolved.height == 430)
    }

    @Test func resolveShapeAppliesTextOverrides() {
        let shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24, fontWeight: 400)
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "ja", label: "Japanese")],
            activeLocaleCode: "ja",
            overrides: ["ja": [shape.id.uuidString: ShapeLocaleOverride(text: "こんにちは", fontSize: 20)]]
        )
        let resolved = LocaleService.resolveShape(shape, localeState: state)
        #expect(resolved.text == "こんにちは")
        #expect(resolved.fontSize == 20)
        #expect(resolved.fontWeight == 400, "Non-overridden properties stay at base value")
    }

    @Test func resolveShapeCanClearRichTextOverride() {
        var shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        shape.richText = "base-rtf"
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(clearsRichText: true)]]
        )

        let resolved = LocaleService.resolveShape(shape, localeState: state)

        #expect(resolved.richText == nil)
    }

    @Test func resolveShapeClearsInheritedRichTextForPlainTextOverride() {
        var shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        shape.richText = "base-rtf"
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )

        let resolved = LocaleService.resolveShape(shape, localeState: state)

        #expect(resolved.text == "Bonjour")
        #expect(resolved.richText == nil)
    }

    @Test func resolveShapeKeepsLocaleRichTextWhenRichTextOverrideExists() {
        var shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        shape.richText = "base-rtf"
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour", richText: "locale-rtf")]]
        )

        let resolved = LocaleService.resolveShape(shape, localeState: state)

        #expect(resolved.text == "Bonjour")
        #expect(resolved.richText == "locale-rtf")
    }

    @Test func resolveShapeAppliesLineHeightMultipleOverride() {
        let shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24, lineSpacing: 12)
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "ja", label: "Japanese")],
            activeLocaleCode: "ja",
            overrides: ["ja": [shape.id.uuidString: ShapeLocaleOverride(lineHeightMultiple: 0.8)]]
        )

        let resolved = LocaleService.resolveShape(shape, localeState: state)

        #expect(resolved.lineHeightMultiple == 0.8)
        #expect(resolved.lineSpacing == 12)
    }

    @Test func resolveShapeAppliesImageOverride() {
        var shape = CanvasShapeModel(type: .device, x: 0, y: 0, width: 200, height: 400, deviceCategory: .iphone)
        shape.screenshotFileName = "base-screenshot.png"
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "de", label: "German")],
            activeLocaleCode: "de",
            overrides: ["de": [shape.id.uuidString: ShapeLocaleOverride(overrideImageFileName: "de-screenshot.png")]]
        )
        let resolved = LocaleService.resolveShape(shape, localeState: state)
        #expect(resolved.screenshotFileName == "de-screenshot.png")
    }

    @Test func resolveShapeNoOverrideReturnsOriginal() {
        let shape = CanvasShapeModel(type: .text, x: 100, y: 200, width: 300, height: 50, text: "Hello")
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )
        let resolved = LocaleService.resolveShape(shape, localeState: state)
        #expect(resolved.text == "Hello")
        #expect(resolved.x == 100)
    }

    // MARK: - resolveShapes batch

    @Test func resolveShapesBatchReturnsOriginalForBaseLocale() {
        let shapes = [
            CanvasShapeModel(type: .rectangle, x: 0, y: 0),
            CanvasShapeModel(type: .text, x: 100, y: 100, text: "Test")
        ]
        let state = LocaleState.default
        let resolved = LocaleService.resolveShapes(shapes, localeState: state)
        #expect(resolved.count == 2)
        #expect(resolved[0].x == 0)
        #expect(resolved[1].text == "Test")
    }

    // MARK: - splitUpdate

    @Test func splitUpdateReturnsUpdatedDirectlyForBaseLocale() {
        var state = LocaleState.default
        let base = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 200, height: 200)
        var updated = base
        updated.x = 150
        updated.width = 300
        let result = LocaleService.splitUpdate(base: base, updated: updated, localeState: &state)
        #expect(result.x == 150, "Base locale: position changes go to base shape directly")
        #expect(result.width == 300)
    }

    @Test func splitUpdateStoresPositionDeltasAsOverrides() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )
        let base = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        var updated = base
        updated.x = 120  // +20 offset
        updated.y = 180  // -20 offset

        let result = LocaleService.splitUpdate(base: base, updated: updated, localeState: &state)

        // Base shape should keep original position
        #expect(result.x == 100)
        #expect(result.y == 200)

        // Override should store deltas
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override?.offsetX == 20)
        #expect(override?.offsetY == -20)
    }

    @Test func splitUpdateStoresTextOverridesForNonBaseLocale() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24)
        var updated = base
        updated.text = "Bonjour"
        updated.fontSize = 20

        let result = LocaleService.splitUpdate(base: base, updated: updated, localeState: &state)

        // Base keeps original text
        #expect(result.text == "Hello")
        #expect(result.fontSize == 24)

        // Override has the French values
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override?.text == "Bonjour")
        #expect(override?.fontSize == 20)
    }

    @Test func splitUpdateStoresRichTextClearForNonBaseLocale() {
        var base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        base.richText = "base-rtf"
        var updated = base
        updated.richText = nil

        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )

        let result = LocaleService.splitUpdate(base: base, updated: updated, localeState: &state)
        let override = state.override(forCode: "fr", shapeId: base.id)

        #expect(result.richText == "base-rtf")
        #expect(override?.clearsRichText == true)
        #expect(override?.richText == nil)
    }

    @Test func splitUpdateStoresLineHeightMultipleOverrideForNonBaseLocale() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24, lineSpacing: 10)
        var updated = base
        updated.lineHeightMultiple = 0.8
        updated.lineSpacing = nil

        let result = LocaleService.splitUpdate(base: base, updated: updated, localeState: &state)
        let override = state.override(forCode: "fr", shapeId: base.id)

        #expect(result.lineHeightMultiple == nil)
        #expect(result.lineSpacing == 10)
        #expect(override?.lineHeightMultiple == 0.8)
    }

    @Test func splitUpdatePreservesOverridesWhenNonOverridablePropertyChanges() {
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24)
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour", fontSize: 20)]]
        )

        // Simulate changing opacity on a resolved shape (non-overridable property)
        var resolved = LocaleService.resolveShape(base, localeState: state)
        #expect(resolved.text == "Bonjour")
        resolved.opacity = 0.5

        let result = LocaleService.splitUpdate(base: base, updated: resolved, localeState: &state)

        // Base shape should get the opacity change but keep base text
        #expect(result.opacity == 0.5)
        #expect(result.text == "Hello")
        #expect(result.fontSize == 24)

        // Override should be preserved
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override?.text == "Bonjour", "Translation must survive non-overridable property changes")
        #expect(override?.fontSize == 20, "Font size override must survive non-overridable property changes")
    }

    @Test func splitUpdateSplitsSimultaneousOverridableAndNonOverridableEdits() {
        // A user editing in a non-base locale changes BOTH an overridable property (text)
        // and a non-overridable property (rotation) on the same shape. splitUpdate must:
        //   - route the rotation change to the base shape (non-overridable),
        //   - update the locale override with the new text,
        //   - keep the base shape's text unchanged.
        let base = CanvasShapeModel(
            type: .text,
            x: 0, y: 0, width: 300, height: 50,
            rotation: 0,
            color: .red, opacity: 1.0,
            text: "Hello", fontSize: 24, fontWeight: 400
        )
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour", fontSize: 22)]]
        )

        // Resolve, then edit text AND rotation at once (simulates a user typing while a rotation gesture is active).
        var edited = LocaleService.resolveShape(base, localeState: state)
        #expect(edited.text == "Bonjour")
        edited.text = "Salut"
        edited.rotation = 45

        let result = LocaleService.splitUpdate(base: base, updated: edited, localeState: &state)

        // Non-overridable rotation lands on the base shape; base text stays put.
        #expect(result.rotation == 45, "Rotation (non-overridable) should be applied to the base shape")
        #expect(result.text == "Hello", "Base shape's text must not change when editing in a non-base locale")

        // The fr override now reflects the new text but keeps the previously-set fontSize override.
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override?.text == "Salut", "Updated text should be stored as the override")
        #expect(override?.fontSize == 22, "Pre-existing fontSize override must survive a same-call edit to a different overridable property")
    }

    @Test func splitUpdateWipesOverridesWhenBaseShapePassedDirectly() {
        // This test documents the bug: passing a base shape (not resolved) to splitUpdate
        // causes overrides to be wiped because all overridable properties match the base.
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24)
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour", fontSize: 20)]]
        )

        // BUG: passing the base shape directly (not resolved) to splitUpdate
        var unresolved = base
        unresolved.opacity = 0.5
        let result = LocaleService.splitUpdate(base: base, updated: unresolved, localeState: &state)

        // The override gets wiped because updated.text == base.text
        #expect(result.opacity == 0.5)
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override == nil, "Bug: override is wiped when base shape is passed as updated")
    }

    @Test func splitUpdateClearsOverrideWhenValuesMatchBase() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [:]]
        )
        let base = CanvasShapeModel(type: .text, x: 100, y: 100, width: 300, height: 50, text: "Hello")
        // Updated matches base exactly — override should be nil
        _ = LocaleService.splitUpdate(base: base, updated: base, localeState: &state)
        let override = state.override(forCode: "fr", shapeId: base.id)
        #expect(override == nil, "No override needed when values match base")
    }

    // MARK: - Override management

    @Test func removeShapeOverridesDeletesFromAllLocales() {
        let shapeId = UUID()
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French"), .init(code: "de", label: "German")],
            activeLocaleCode: "fr",
            overrides: [
                "fr": [shapeId.uuidString: ShapeLocaleOverride(text: "Bonjour")],
                "de": [shapeId.uuidString: ShapeLocaleOverride(text: "Hallo")]
            ]
        )
        LocaleService.removeShapeOverrides(&state, shapeId: shapeId)
        #expect(state.override(forCode: "fr", shapeId: shapeId) == nil)
        #expect(state.override(forCode: "de", shapeId: shapeId) == nil)
    }

    @Test func copyShapeOverridesDuplicatesAcrossLocales() {
        let sourceId = UUID()
        let targetId = UUID()
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [
                "fr": [sourceId.uuidString: ShapeLocaleOverride(offsetX: 10, text: "Bonjour")]
            ]
        )
        LocaleService.copyShapeOverrides(&state, fromId: sourceId, toId: targetId)
        let copied = state.override(forCode: "fr", shapeId: targetId)
        #expect(copied?.text == "Bonjour")
        #expect(copied?.offsetX == 10)
    }

    // MARK: - Locale lifecycle

    @Test func addLocalePreventsDeduplication() {
        var state = LocaleState.default // has "en"
        LocaleService.addLocale(&state, locale: .init(code: "fr", label: "French"))
        #expect(state.locales.count == 2)
        LocaleService.addLocale(&state, locale: .init(code: "fr", label: "French"))
        #expect(state.locales.count == 2, "Should not add duplicate locale")
    }

    @Test func removeLocaleDeletesOverridesAndResetsActive() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [UUID().uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )
        LocaleService.removeLocale(&state, code: "fr")
        #expect(state.locales.count == 1)
        #expect(state.activeLocaleCode == "en", "Should reset to base locale")
        #expect(state.overrides["fr"] == nil, "Should remove all overrides for deleted locale")
    }

    @Test func removeBaseLocaleIsNoOp() {
        var state = LocaleState.default
        LocaleService.removeLocale(&state, code: "en")
        #expect(state.locales.count == 1, "Cannot remove base locale")
    }

    // MARK: - setBaseLocale (change base locale)

    /// Promote `code` to base for a single shape and return the new base shape.
    private func promote(_ code: String, shape: CanvasShapeModel, state: inout LocaleState) -> CanvasShapeModel {
        var rows = [ScreenshotRow(shapes: [shape])]
        LocaleService.setBaseLocale(code, rows: &rows, state: &state)
        return rows[0].shapes[0]
    }

    @Test func setBaseLocaleBakesTranslationIntoBaseAndAnchorsOldBase() {
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello", fontSize: 24)
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour", fontSize: 20)]]
        )

        let newBase = promote("fr", shape: base, state: &state)

        #expect(newBase.text == "Bonjour")
        #expect(newBase.fontSize == 20)
        #expect(state.baseLocaleCode == "fr", "Promoted locale moves to front")
        #expect(state.override(forCode: "fr", shapeId: base.id) == nil, "Promoted locale drops its override")
        let enOverride = state.override(forCode: "en", shapeId: base.id)
        #expect(enOverride?.text == "Hello", "Old base becomes a translation")
        #expect(enOverride?.fontSize == 24)
    }

    @Test func setBaseLocaleInvertsPositionOffsets() {
        let base = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French"), .init(code: "de", label: "German")],
            activeLocaleCode: "fr",
            overrides: [
                "fr": [base.id.uuidString: ShapeLocaleOverride(offsetX: 10, offsetY: -20)],
                "de": [base.id.uuidString: ShapeLocaleOverride(offsetX: 30, offsetY: 5)],
            ]
        )

        let newBase = promote("fr", shape: base, state: &state)

        #expect(newBase.x == 110)
        #expect(newBase.y == 180)
        // en (old base) re-anchored relative to fr: 100-110 = -10, 200-180 = 20
        let enOverride = state.override(forCode: "en", shapeId: base.id)
        #expect(enOverride?.offsetX == -10)
        #expect(enOverride?.offsetY == 20)
        // de re-anchored relative to fr: 30-10 = 20, 5-(-20) = 25
        let deOverride = state.override(forCode: "de", shapeId: base.id)
        #expect(deOverride?.offsetX == 20)
        #expect(deOverride?.offsetY == 25)
    }

    @Test func setBaseLocaleMovesImageOverrideToBase() {
        var base = CanvasShapeModel(type: .image, x: 0, y: 0, width: 300, height: 400)
        base.imageFileName = "en.png"
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(overrideImageFileName: "fr.png")]]
        )

        let newBase = promote("fr", shape: base, state: &state)

        #expect(newBase.displayImageFileName == "fr.png")
        #expect(state.override(forCode: "en", shapeId: base.id)?.overrideImageFileName == "en.png")
    }

    @Test func setBaseLocaleWithoutOverrideLeavesNoOldBaseOverride() {
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: [:]
        )

        let newBase = promote("fr", shape: base, state: &state)

        #expect(newBase.text == "Hello", "Untranslated shape keeps its content")
        #expect(state.override(forCode: "en", shapeId: base.id) == nil, "No override when content is identical")
    }

    @Test func setBaseLocaleToCurrentBaseIsNoOp() {
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "en",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )

        let result = promote("en", shape: base, state: &state)

        #expect(result.text == "Hello", "Promoting the existing base changes nothing")
        #expect(state.baseLocaleCode == "en")
        #expect(state.override(forCode: "fr", shapeId: base.id)?.text == "Bonjour")
    }

    @Test func setBaseLocaleIsReversible() {
        let base = CanvasShapeModel(type: .text, x: 100, y: 200, width: 300, height: 50, text: "Hello", fontSize: 24)
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French"), .init(code: "de", label: "German")],
            activeLocaleCode: "en",
            overrides: [
                "fr": [base.id.uuidString: ShapeLocaleOverride(offsetX: 10, text: "Bonjour", fontSize: 20)],
                "de": [base.id.uuidString: ShapeLocaleOverride(offsetY: 5, text: "Hallo")],
            ]
        )

        func resolvedAll(_ shape: CanvasShapeModel, _ s: LocaleState) -> [String: CanvasShapeModel] {
            Dictionary(uniqueKeysWithValues: s.locales.map {
                ($0.code, LocaleService.resolveShape(shape, localeCode: $0.code, localeState: s))
            })
        }

        let originalResolved = resolvedAll(base, state)

        // Promote fr, then promote en back.
        let promoted = promote("fr", shape: base, state: &state)
        let back = promote("en", shape: promoted, state: &state)

        #expect(state.baseLocaleCode == "en", "Base returns to en")
        let roundTripped = resolvedAll(back, state)
        for code in ["en", "fr", "de"] {
            #expect(roundTripped[code]?.text == originalResolved[code]?.text, "\(code) text preserved")
            #expect(roundTripped[code]?.x == originalResolved[code]?.x, "\(code) x preserved")
            #expect(roundTripped[code]?.y == originalResolved[code]?.y, "\(code) y preserved")
            #expect(roundTripped[code]?.fontSize == originalResolved[code]?.fontSize, "\(code) fontSize preserved")
        }
    }

    @Test func setBaseLocaleToleratesDuplicateLocaleCodes() {
        let base = CanvasShapeModel(type: .text, x: 0, y: 0, width: 300, height: 50, text: "Hello")
        // A malformed/duplicate-code locale list must not crash (regression guard).
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French"), .init(code: "fr", label: "French dup")],
            activeLocaleCode: "en",
            overrides: ["fr": [base.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )

        let newBase = promote("fr", shape: base, state: &state)

        #expect(newBase.text == "Bonjour")
        #expect(state.baseLocaleCode == "fr")
    }
}

struct LocaleOverrideFieldTests {

    /// Every `LocaleOverrideField` is reachable from `makeOverride` — a case that no override can
    /// ever set would mark and offer to reset a property that doesn't exist.
    ///
    /// Note this is only one direction. `overriddenFields` filters `allCases`, so it cannot report
    /// a field that has no case; the reverse guard — a *stored property* gaining no case — is
    /// `storedFieldCountIsPinned` below.
    @Test func everyOverrideFieldIsReachableFromMakeOverride() {
        var textBase = CanvasShapeModel(type: .text, x: 0, y: 0, width: 100, height: 50, text: "a", fontSize: 10, fontWeight: 400)
        textBase.fontName = "Helvetica"
        textBase.textAlign = .left
        textBase.italic = false
        textBase.uppercase = false
        textBase.letterSpacing = 0
        textBase.lineSpacing = 0
        textBase.lineHeightMultiple = 1

        var textResolved = textBase
        textResolved.x = 5
        textResolved.y = 6
        textResolved.width = 110
        textResolved.height = 60
        textResolved.text = "b"
        textResolved.richText = "rtf"
        textResolved.fontName = "Times"
        textResolved.fontSize = 20
        textResolved.fontWeight = 700
        textResolved.textAlign = .right
        textResolved.italic = true
        textResolved.uppercase = true
        textResolved.letterSpacing = 2
        textResolved.lineSpacing = 3
        textResolved.lineHeightMultiple = 1.5

        var imageBase = CanvasShapeModel(type: .image, x: 0, y: 0, width: 10, height: 10)
        imageBase.imageFileName = "base.png"
        var imageResolved = imageBase
        imageResolved.imageFileName = "other.png"

        let covered = (LocaleService.makeOverride(base: textBase, resolved: textResolved)?.overriddenFields ?? [])
            .union(LocaleService.makeOverride(base: imageBase, resolved: imageResolved)?.overriddenFields ?? [])

        #expect(covered == Set(LocaleOverrideField.allCases))
    }

    /// The guard `everyOverrideFieldIsReachableFromMakeOverride` structurally cannot give: adding a
    /// stored property to `ShapeLocaleOverride` without a matching `LocaleOverrideField` case would
    /// leave that property unmarked and with no per-field reset, and no other test would notice.
    /// Listing the names rather than counting them means a failure says *which* property is new.
    @Test func everyStoredOverridePropertyHasAField() {
        let stored = Set(Mirror(reflecting: ShapeLocaleOverride()).children.compactMap(\.label))

        #expect(stored == [
            "offsetX", "offsetY", "offsetWidth", "offsetHeight",
            // All three are LocaleOverrideField.text — translated text moves as one unit.
            "text", "richText", "clearsRichText",
            "fontName", "fontSize", "fontWeight", "textAlign", "italic", "uppercase",
            "letterSpacing", "lineSpacing", "lineHeightMultiple",
            "overrideImageFileName",
        ])
    }

    @Test func clearRemovesExactlyOneField() {
        let full = ShapeLocaleOverride(
            offsetX: 1, offsetY: 2, offsetWidth: 3, offsetHeight: 4,
            text: "t", fontName: "F", fontSize: 12, fontWeight: 700,
            textAlign: .right, italic: true, uppercase: true,
            letterSpacing: 1, lineSpacing: 2, lineHeightMultiple: 1.5,
            overrideImageFileName: "i.png"
        )
        #expect(full.overriddenFields == Set(LocaleOverrideField.allCases))

        for field in LocaleOverrideField.allCases {
            var copy = full
            field.clear(in: &copy)
            #expect(copy.overriddenFields == Set(LocaleOverrideField.allCases).subtracting([field]),
                    "Clearing \(field) must leave every other field untouched")
        }
    }

    /// Translated text lives under the shape's `textTranslationKey`, styling under its id. A shape
    /// whose text is reused would otherwise report no text override at all.
    @Test func overriddenFieldsMergesSharedTextKey() {
        var shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 100, height: 50, text: "Hello")
        shape.translationKey = "shared-key"
        let state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [
                shape.id.uuidString: ShapeLocaleOverride(offsetX: 12),
                "shared-key": ShapeLocaleOverride(text: "Bonjour"),
            ]]
        )

        let fields = LocaleService.overriddenFields(for: shape, localeCode: "fr", localeState: state)

        #expect(fields == [.positionX, .text])
    }

    @Test func overriddenFieldsIsEmptyForBaseLocale() {
        let shape = CanvasShapeModel(type: .text, x: 0, y: 0, width: 100, height: 50, text: "Hello")
        let state = LocaleState(
            locales: [.init(code: "en", label: "English")],
            activeLocaleCode: "en",
            overrides: ["en": [shape.id.uuidString: ShapeLocaleOverride(offsetX: 12)]]
        )

        #expect(LocaleService.overriddenFields(for: shape, localeCode: "en", localeState: state).isEmpty)
    }
}
