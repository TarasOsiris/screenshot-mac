import Foundation

/// Builds a self-contained prompt that an external AI agent can use to localize a project's
/// translations by editing its `translations.xcstrings` String Catalog in place. Bundles the
/// catalog path, an explanation of the String Catalog format, and the recognized locale codes.
enum LocalizationPromptService {
    static func prompt(forProjectId id: UUID) -> String {
        let path = PersistenceService.translationCatalogURL(id).path
        let localeList = LocaleDefinition.catalog
            .map { "- `\($0.code)` — \($0.label)" }
            .joined(separator: "\n")

        return """
        You are localizing a **Screenshot Bro** project. Screenshot Bro generates App Store / Google Play marketing screenshots. The text overlays shown on the screenshots are stored in an Apple **String Catalog** (`.xcstrings`) file. Your job is to translate those overlays into one or more target languages by editing that file in place.

        ## Catalog file

        Edit this file directly:

        ```
        \(path)
        ```

        ## How the catalog works

        It is a standard Apple String Catalog — a JSON file with this shape:

        ```json
        {
          "sourceLanguage": "en",
          "version": "1.0",
          "strings": {
            "<SHAPE-UUID>": {
              "comment": "Row: Hero",
              "localizations": {
                "en": { "stringUnit": { "state": "translated", "value": "Track every match" } },
                "de": { "stringUnit": { "state": "translated", "value": "Verfolge jedes Match" } }
              }
            }
          }
        }
        ```

        - Each key under `strings` is a text shape's UUID — **never change, add, or remove these keys**.
        - `sourceLanguage` is the base language. Each entry's `localizations[sourceLanguage].stringUnit.value` is the **base string to translate from**. Treat it as read-only.
        - `comment` (when present) gives context (the screenshot row the text appears in).

        ## Steps

        1. Read the catalog. For each entry under `strings`, note its base string (the `value` under `sourceLanguage`).
        2. For each target language and each entry, add or update `localizations[<code>] = { "stringUnit": { "state": "translated", "value": "<translation>" } }`. Use the language codes the app recognizes, listed below. Leave the base (`sourceLanguage`) localization unchanged.
        3. Write the file back as valid JSON. Do not change `sourceLanguage`, `version`, the entry keys, or any `comment`. Only add/modify non-base `localizations`.

        ## Translation guidance

        - Keep translations concise — these render inside fixed screenshot layouts, so avoid making strings dramatically longer than the original.
        - Preserve product/brand names, emoji, and any intentional capitalization style.
        - Match the tone of marketing copy (punchy, benefit-led), not literal word-for-word translation.
        - Don't translate placeholder-looking tokens or URLs.

        ## Recognized language codes

        Use these `code` / `label` pairs (BCP-47-style codes the app understands):

        \(localeList)
        """
    }
}
