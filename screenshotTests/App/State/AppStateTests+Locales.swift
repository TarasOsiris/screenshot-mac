import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension AppStateTests {
    // MARK: - Locale operations via AppState

    @Test func addLocaleUpdatesState() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        #expect(state.localeState.locales.count == 1)
        state.addLocale(.init(code: "fr", label: "French"))
        #expect(state.localeState.locales.count == 2)
        #expect(state.localeState.locales.last?.code == "fr")
    }

    @Test func cycleLocaleForwardAndBackward() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }
        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        // addLocale sets active to the newly added locale
        state.setActiveLocale("en")
        #expect(state.localeState.activeLocaleCode == "en")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "fr")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "de")

        state.cycleLocaleForward()
        #expect(state.localeState.activeLocaleCode == "en", "Should wrap around")

        state.cycleLocaleBackward()
        #expect(state.localeState.activeLocaleCode == "de", "Should wrap backward")
    }

    @Test func translateShapesUsesRequestedLocaleForMissingCheck() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.updateTranslationText(shapeId: shape.id, localeCode: "de", text: "Hallo")
        state.setActiveLocale("de")

        await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: true
        ) { _ in
            "Bonjour"
        }

        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == "Bonjour")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == "Hallo")
    }

    @Test func translateShapesWritesToRequestedLocaleEvenIfActiveLocaleChanges() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)
        state.setActiveLocale("fr")

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: false
        ) { text in
            state.setActiveLocale("de")
            return "\(text)-fr"
        }

        #expect(state.localeState.activeLocaleCode == "de")
        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == "Hello-fr")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == nil)
    }

    @Test func translateShapesPreservesLineBreaksWithoutExtraSpaces() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello\nWorld"
        state.addShape(shape)

        var translatedInputs: [String] = []
        await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: false
        ) { text in
            translatedInputs.append(text)
            return text
                .replacingOccurrences(of: "Hello", with: "Bonjour")
                .replacingOccurrences(of: "World", with: "Monde")
        }

        #expect(translatedInputs.count == 1)
        #expect(translatedInputs.first?.contains("Hello") == true)
        #expect(translatedInputs.first?.contains("World") == true)
        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == "Bonjour\nMonde")
    }

    @Test func autoTranslateMissingSkipsRichTextOnlyOverride() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        // Format the German translation without changing the plain text — this yields a
        // rich-text-only override (override.richText set, override.text nil), the exact case
        // that auto-translate-missing used to mistake for "untranslated" and overwrite.
        state.setActiveLocale("de")
        var formatted = shape
        formatted.richText = "BASE64_RTF_DE"
        state.updateShape(formatted)

        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.richText == "BASE64_RTF_DE")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == nil)
        #expect(state.translationProgress(for: "de").translated == 1)

        var translateCalled = false
        await translateShapes(
            state: state,
            targetLocaleCode: "de",
            onlyUntranslated: true
        ) { _ in
            translateCalled = true
            return "Hallo"
        }

        #expect(translateCalled == false)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.richText == "BASE64_RTF_DE")
    }

    @Test func resetTranslationClearsRichTextOnlyOverride() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.setActiveLocale("de")
        var formatted = shape
        formatted.richText = "BASE64_RTF_DE"
        state.updateShape(formatted)
        #expect(state.translationProgress(for: "de").translated == 1)

        state.resetTranslationText(shapeId: shape.id, localeCode: "de")

        #expect(state.localeState.override(forCode: "de", shapeId: shape.id) == nil)
        #expect(state.translationProgress(for: "de").translated == 0)
    }

    @Test func retranslateAllClearsExistingRichTextOverride() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.setActiveLocale("de")
        var formatted = shape
        formatted.richText = "BASE64_RTF_DE"
        state.updateShape(formatted)
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.richText == "BASE64_RTF_DE")

        await translateShapes(
            state: state,
            targetLocaleCode: "de",
            onlyUntranslated: false
        ) { _ in
            "Hallo"
        }

        let override = state.localeState.override(forCode: "de", shapeId: shape.id)
        #expect(override?.text == "Hallo")
        #expect(override?.richText == nil)
    }

    /// Terms are always translated from the base locale: even when a non-base override already
    /// exists for the target, the text fed to the translator is the base shape text, never the
    /// existing override.
    @Test func translateAlwaysUsesBaseLocaleTextAsSource() async {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "de", label: "German"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)
        // A pre-existing manual German translation must NOT become the source text.
        state.updateTranslationText(shapeId: shape.id, localeCode: "de", text: "Hallo")

        var receivedSource: String?
        await translateShapes(
            state: state,
            targetLocaleCode: "de",
            onlyUntranslated: false
        ) { src in
            receivedSource = src
            return "Hallo (auto)"
        }

        #expect(receivedSource == "Hello")
        #expect(state.localeState.override(forCode: "de", shapeId: shape.id)?.text == "Hallo (auto)")
    }

    @Test func translatePreservingLineBreaksKeepsBlankLinesAndLinePadding() async throws {
        var translatedInputs: [String] = []
        let translated = try await translatePreservingLineBreaks("  Hello\n\nWorld  \r\nAgain") { text in
            translatedInputs.append(text)
            return text
                .replacingOccurrences(of: "Hello", with: "Bonjour")
                .replacingOccurrences(of: "World", with: "Monde")
                .replacingOccurrences(of: "Again", with: "Encore")
        }

        #expect(translatedInputs.count == 1)
        #expect(translatedInputs.first?.contains("Hello") == true)
        #expect(translatedInputs.first?.contains("World") == true)
        #expect(translatedInputs.first?.contains("Again") == true)
        #expect(translated == "  Bonjour\n\nMonde  \r\nEncore")
    }

    @Test func translatePreservingLineBreaksUsesSentinelWithNoTranslatableContent() async throws {
        // The newline sentinel handed to the translator must carry no real words
        // or ASCII digits — those could be translated, stripped, or localized by
        // the engine, dropping the newline and leaking garbled text. Only the
        // original characters, spaces, and Private Use Area scalars may appear.
        var seenByTranslator = ""
        _ = try await translatePreservingLineBreaks("1\n2") { text in
            seenByTranslator = text
            return text
        }

        #expect(!seenByTranslator.contains("LINE_BREAK"))
        for scalar in seenByTranslator.unicodeScalars {
            let isOriginal = scalar == "1" || scalar == "2"
            let isSpace = scalar == " "
            let isPrivateUse = lineBreakSentinelRange.contains(scalar.value)
            #expect(isOriginal || isSpace || isPrivateUse)
        }
    }

    @Test func updateTranslationTextIgnoresRemovedLocale() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.removeLocale("fr")
        state.updateTranslationText(shapeId: shape.id, localeCode: "fr", text: "Bonjour")

        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == nil)
        #expect(state.localeState.overrides["fr"] == nil)
    }

    @Test func updateTranslationTextIgnoresDeletedShape() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.addLocale(.init(code: "fr", label: "French"))
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 1344)
        shape.text = "Hello"
        state.addShape(shape)

        state.deleteShape(shape.id)
        state.updateTranslationText(shapeId: shape.id, localeCode: "fr", text: "Bonjour")

        #expect(state.localeState.override(forCode: "fr", shapeId: shape.id)?.text == nil)
        #expect(state.localeState.overrides["fr"] == nil)
    }
}
