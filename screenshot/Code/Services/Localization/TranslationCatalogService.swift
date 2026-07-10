import Foundation

/// Reads and writes a project's `translations.xcstrings` String Catalog, using the same
/// file-coordination strategy as `PersistenceService` so it stays iCloud-safe. The catalog
/// lives inside the project directory, so directory-level copies (duplication, iCloud
/// dir replacement) carry it along automatically.
nonisolated enum TranslationCatalogService {
    /// Pretty-printed + sorted so a translator-edited file produces minimal diffs and slashes
    /// in values aren't escaped.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return e
    }()

    static func read(projectId: UUID) -> TranslationCatalog? {
        PersistenceService.load(TranslationCatalog.self, from: PersistenceService.translationCatalogURL(projectId))
    }

    /// Catalog-wins merge: overlay the project's translator-editable `.xcstrings` text onto
    /// `localeState`. Returns `localeState` unchanged when no catalog exists (old project, first
    /// run). The single source of truth for both project load and on-activation refresh.
    static func merging(_ localeState: LocaleState, projectId: UUID, rows: [ScreenshotRow]) -> LocaleState {
        guard let catalog = read(projectId: projectId) else { return localeState }
        var merged = localeState
        catalog.apply(to: &merged, validKeys: TranslationCatalog.representedKeys(rows: rows))
        return merged
    }

    static func exists(projectId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: PersistenceService.translationCatalogURL(projectId).path)
    }

    static func write(_ catalog: TranslationCatalog, projectId: UUID) throws {
        let data = try encoder.encode(catalog)
        try PersistenceService.writeData(data, to: PersistenceService.translationCatalogURL(projectId))
    }

    static func delete(projectId: UUID) throws {
        try PersistenceService.removeItemIfExists(at: PersistenceService.translationCatalogURL(projectId))
    }
}
