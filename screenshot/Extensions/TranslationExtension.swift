import Translation

extension Optional where Wrapped == TranslationSession.Configuration {
    /// Creates a new configuration or invalidates the existing one to re-trigger `.translationTask`.
    mutating func refresh(source: String, target: String) {
        if self != nil {
            self?.invalidate()
        } else {
            self = .init(
                source: .init(identifier: source),
                target: .init(identifier: target)
            )
        }
    }
}
