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

/// Translate text shapes using the given session.
func translateShapes(
    session: TranslationSession,
    state: AppState,
    onlyUntranslated: Bool = true,
    shapeFilter: ((UUID) -> Bool)? = nil
) async {
    let items = state.textShapesForTranslation()
    for item in items {
        if let filter = shapeFilter, !filter(item.shape.id) { continue }
        if onlyUntranslated && !isUntranslated(item.overrideText) { continue }
        guard let baseText = item.shape.text, !baseText.isEmpty else { continue }
        do {
            let response = try await session.translate(baseText)
            state.updateTranslationText(shapeId: item.shape.id, text: response.targetText)
        } catch {
            print("Translation failed for shape \(item.shape.id): \(error)")
        }
    }
}
