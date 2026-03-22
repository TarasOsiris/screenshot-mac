import Translation

extension Optional where Wrapped == TranslationSession.Configuration {
    /// Creates or re-triggers a configuration for the language pair.
    /// First call creates a new config; subsequent calls invalidate the existing
    /// tracked config so `.translationTask` re-fires reliably.
    mutating func refresh(source: String, target: String) {
        let newSource = Locale.Language(identifier: source)
        let newTarget = Locale.Language(identifier: target)
        if let existing = self, existing.source == newSource, existing.target == newTarget {
            // Same language pair — invalidate in-place so .translationTask re-fires.
            // Creating a new config doesn't work: SwiftUI treats same-source/target as equal.
            self?.invalidate()
        } else {
            self = .init(source: newSource, target: newTarget)
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
