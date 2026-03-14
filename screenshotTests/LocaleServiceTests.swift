import Testing
import Foundation
@testable import Screenshot_Bro

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

    @Test func splitUpdateClearsOverrideWhenValuesMatchBase() {
        var state = LocaleState(
            locales: [.init(code: "en", label: "English"), .init(code: "fr", label: "French")],
            activeLocaleCode: "fr",
            overrides: ["fr": [:]]
        )
        let base = CanvasShapeModel(type: .text, x: 100, y: 100, width: 300, height: 50, text: "Hello")
        // Updated matches base exactly — override should be nil
        let result = LocaleService.splitUpdate(base: base, updated: base, localeState: &state)
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
}
