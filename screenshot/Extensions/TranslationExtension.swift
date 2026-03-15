import Translation

extension Optional where Wrapped == TranslationSession.Configuration {
    /// Creates or re-triggers a configuration for the language pair.
    /// First call creates a new config; subsequent calls invalidate to re-trigger `.translationTask`.
    mutating func refresh(source: String, target: String) {
        if self != nil {
            // Recreate with new language pair and invalidate to ensure re-trigger
            var config = TranslationSession.Configuration(
                source: .init(identifier: source),
                target: .init(identifier: target)
            )
            config.invalidate()
            self = config
        } else {
            self = .init(
                source: .init(identifier: source),
                target: .init(identifier: target)
            )
        }
    }
}

/// Whether a translation item's override text is empty (i.e. not yet translated).
func isUntranslated(_ overrideText: String?) -> Bool {
    (overrideText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// Translate text shapes for a specific locale using a caller-provided translation function.
func translateShapes(
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil,
    translate: @escaping (String) async throws -> String
) async {
    let items = state.textShapesForTranslation(localeCode: targetLocaleCode)
    for item in items {
        if let filter = shapeFilter, !filter(item.shape.id) { continue }
        if onlyUntranslated && !isUntranslated(item.overrideText) { continue }
        guard let baseText = item.shape.text, !baseText.isEmpty else { continue }
        do {
            let translatedText = try await translate(baseText)
            state.updateTranslationText(
                shapeId: item.shape.id,
                localeCode: targetLocaleCode,
                text: translatedText
            )
        } catch {
            print("Translation failed for shape \(item.shape.id): \(error)")
        }
    }
}

/// Translate text shapes using the given session.
func translateShapes(
    session: TranslationSession,
    state: AppState,
    targetLocaleCode: String,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil
) async {
    await translateShapes(
        state: state,
        targetLocaleCode: targetLocaleCode,
        onlyUntranslated: onlyUntranslated,
        shapeFilter: shapeFilter
    ) { baseText in
        let response = try await session.translate(baseText)
        return response.targetText
    }
}
