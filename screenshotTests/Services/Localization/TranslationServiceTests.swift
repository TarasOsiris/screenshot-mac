import Foundation
@testable import Screenshot_Bro
import Testing
import Translation

private struct TranslatorFailure: Error {}

@Suite(.serialized)
@MainActor
struct TranslationServiceTests {

    /// A state with a French locale and one text shape per entry in `texts`, in that order.
    private func makeState(texts: [String]) -> (AppState, URL, [CanvasShapeModel]) {
        let (state, tempDir) = makeTestState()
        state.addLocale(.init(code: "fr", label: "French"))
        state.setActiveLocale(state.localeState.baseLocaleCode)
        state.selectRow(state.rows[0].id)
        let shapes = texts.enumerated().map { index, text in
            var shape = CanvasShapeModel.defaultText(centerX: 621, centerY: 400 + CGFloat(index) * 300)
            shape.text = text
            state.addShape(shape)
            return shape
        }
        return (state, tempDir, shapes)
    }

    private func frenchText(_ state: AppState, _ shape: CanvasShapeModel) -> String? {
        state.localeState.override(forCode: "fr", shapeId: shape.id)?.text
    }

    // MARK: - isUntranslated

    @Test(arguments: [nil, "", "   ", " \n\t "] as [String?])
    func blankOverridesCountAsUntranslated(_ text: String?) {
        #expect(isUntranslated(text))
    }

    @Test(arguments: ["Bonjour", "  x  "])
    func anyVisibleCharacterCountsAsTranslated(_ text: String) {
        #expect(!isUntranslated(text))
    }

    // MARK: - translateShapes(state:translate:)

    /// One failure stops the run, so the language-download prompt isn't re-shown per shape.
    @Test func firstFailureStopsTheRunAndKeepsEarlierTranslations() async {
        let (state, tempDir, shapes) = makeState(texts: ["One", "Two", "Three"])
        defer { cleanupTestState(tempDir) }

        var requests: [String] = []
        let completed = await translateShapes(state: state, targetLocaleCode: "fr", onlyUntranslated: false) { text in
            requests.append(text)
            if requests.count == 2 { throw TranslatorFailure() }
            return "fr:\(text)"
        }

        #expect(completed == false)
        #expect(requests.count == 2)
        #expect(shapes.compactMap { frenchText(state, $0) } == requests.prefix(1).map { "fr:\($0)" })
    }

    @Test func emptyBaseTextAndFilteredShapesAreNeverSent() async {
        let (state, tempDir, shapes) = makeState(texts: ["Keep", "", "Filtered"])
        defer { cleanupTestState(tempDir) }
        let filteredId = shapes[2].id

        var requests: [String] = []
        let completed = await translateShapes(
            state: state,
            targetLocaleCode: "fr",
            onlyUntranslated: false,
            shapeFilter: { $0 != filteredId }
        ) { text in
            requests.append(text)
            return "fr:\(text)"
        }

        #expect(completed)
        #expect(requests == ["Keep"])
        #expect(frenchText(state, shapes[0]) == "fr:Keep")
        #expect(frenchText(state, shapes[1]) == nil)
        #expect(frenchText(state, shapes[2]) == nil)
    }

    /// A whitespace-only override is blank, so translate-missing must fill it rather than skip it.
    @Test func onlyUntranslatedSkipsRealTranslationsButFillsBlankOnes() async {
        let (state, tempDir, shapes) = makeState(texts: ["Hello", "World"])
        defer { cleanupTestState(tempDir) }
        state.updateTranslationText(shapeId: shapes[0].id, localeCode: "fr", text: "Bonjour")
        state.updateTranslationText(shapeId: shapes[1].id, localeCode: "fr", text: "   ")

        var requests: [String] = []
        let completed = await translateShapes(state: state, targetLocaleCode: "fr", onlyUntranslated: true) { text in
            requests.append(text)
            return "fr:\(text)"
        }

        #expect(completed)
        #expect(requests == ["World"])
        #expect(frenchText(state, shapes[0]) == "Bonjour")
        #expect(frenchText(state, shapes[1]) == "fr:World")
    }

    // MARK: - validatedTargetText

    private func response(target: String, text: String = "Hallo") -> TranslationSession.Response {
        TranslationSession.Response(
            sourceLanguage: Locale.Language(identifier: "en"),
            targetLanguage: Locale.Language(identifier: target),
            sourceText: "Hello",
            targetText: text
        )
    }

    @Test func responseInTheRequestedLanguageIsAccepted() throws {
        #expect(try validatedTargetText(response(target: "de"), requestedTarget: "de") == "Hallo")
    }

    /// Only the language code is compared, so a regional request accepts the bare language back.
    @Test func regionAndScriptDifferencesAreAccepted() throws {
        #expect(try validatedTargetText(response(target: "pt", text: "Olá"), requestedTarget: "pt-BR") == "Olá")
        #expect(try validatedTargetText(response(target: "zh-Hant", text: "你好"), requestedTarget: "zh-Hans") == "你好")
    }

    @Test func silentFallbackToAnotherLanguageIsRejected() {
        do {
            _ = try validatedTargetText(response(target: "fr", text: "Bonjour"), requestedTarget: "de")
            Issue.record("expected WrongTargetLanguageError")
        } catch let error as WrongTargetLanguageError {
            #expect(error.requested == "de")
            #expect(error.returned == "fr")
        } catch {
            Issue.record("expected WrongTargetLanguageError, got \(error)")
        }
    }

    // MARK: - Configuration refresh

    @Test func refreshCreatesThenReTriggersThenReplacesTheConfiguration() throws {
        var config: TranslationSession.Configuration?

        config.refresh(source: "en", target: "de")
        let first = try #require(config)
        #expect(first.source == Locale.Language(identifier: "en"))
        #expect(first.target == Locale.Language(identifier: "de"))

        config.refresh(source: "en", target: "de")
        let retriggered = try #require(config)
        #expect(retriggered.target == first.target)
        #expect(retriggered.version != first.version, "same pair must invalidate so .translationTask re-fires")
        #expect(retriggered != first)

        config.refresh(source: "en", target: "fr")
        #expect(config?.target == Locale.Language(identifier: "fr"))
    }

    // MARK: - TranslationLanguageIssue

    @Test func runResultsMapToTheMatchingIssue() {
        #expect(TranslationLanguageIssue(.languagesNotDownloaded, language: "German") == .notDownloaded(language: "German"))
        #expect(TranslationLanguageIssue(.unsupportedPair, language: "German") == .unsupported(language: "German"))
        #expect(TranslationLanguageIssue(.downloadFailed, language: "German") == .failed(language: "German"))
        #expect(TranslationLanguageIssue(.translationFailed, language: "German") == .failed(language: "German"))
    }

    /// System Settings only helps when a model is missing; the other cases must not send the user there.
    @Test func onlyAMissingDownloadOffersSettings() {
        #expect(TranslationLanguageIssue.notDownloaded(language: "German").offersSettings)
        #expect(!TranslationLanguageIssue.unsupported(language: "German").offersSettings)
        #expect(!TranslationLanguageIssue.failed(language: "German").offersSettings)
    }

    /// `id` drives `.alert(item:)`, so a different kind or language must present a fresh alert.
    @Test func issueIdsDistinguishKindAndLanguage() {
        let issues: [TranslationLanguageIssue] = [
            .notDownloaded(language: "German"), .unsupported(language: "German"), .failed(language: "German"),
            .notDownloaded(language: "French"),
        ]
        #expect(Set(issues.map(\.id)).count == issues.count)
    }
}
