import Foundation

/// Builds a self-contained prompt that an external AI agent can use to localize a
/// project's `project.json` file in place. Bundles the project path, an explanation
/// of how locale overrides are stored, and the on-disk schema.
enum LocalizationPromptService {
    static func prompt(forProjectId id: UUID) -> String {
        let path = PersistenceService.projectDataURL(id).path
        let resources = PersistenceService.resourcesDir(id).path
        let localeList = LocaleDefinition.catalog
            .map { "- `\($0.code)` — \($0.label)" }
            .joined(separator: "\n")
        let schemaSection = bundledSchema().map { "\n\n## Project schema (JSON Schema, Draft 2020-12)\n\nThe `project.json` conforms to this schema. Field names are short codes; each `description` maps the code to its meaning.\n\n```json\n\($0)\n```" } ?? ""

        return """
        You are localizing a **Screenshot Bro** project. Screenshot Bro generates App Store / Google Play marketing screenshots. A project is a single JSON file describing rows of screenshots; each row contains text overlays, device frames, and images. Your job is to translate the text overlays into one or more target languages by editing that JSON file in place.

        ## Project file

        Edit this file directly:

        ```
        \(path)
        ```

        Image assets it references live in `\(resources)` (you do not need to touch these for a text-only localization).

        ## How localization works

        The file's top-level keys are `r` (rows), `ls` (localeState), and `m` (modifiedAt). All localization lives under `ls`:

        - `ls.l` — ordered array of locales, each `{ "c": <code>, "l": <label> }`. **The first entry is the base locale** and is shown as-is. Every other entry is a translation layer.
        - `ls.alc` — the currently active locale code (leave it as the base locale's code).
        - `ls.o` — overrides, a nested map: `localeCode → shapeUUID(string) → override`. This is where translations go.

        Base (untranslated) text lives on the text shapes themselves. Each row in `r` has a `s` array of shapes; a text shape has `"t": "text"`, an `id` (UUID), and its content in `txt` (plain text) and/or `rt` (base64-encoded RTF for per-range styling). Only shapes with `"t": "text"` need translating.

        A locale override (`ls.o[code][shapeId]`) only needs the translated string in its `txt` field:

        ```json
        "ls": {
          "o": {
            "de": {
              "1F2E…-UUID-of-text-shape": { "txt": "Übersetzter Text" }
            }
          }
        }
        ```

        Important behavior: setting an override's `txt` **without** an `rt` automatically drops the base shape's rich-text styling for that locale and renders the plain translated string — so you do **not** need to decode/re-encode RTF. Just provide `txt`.

        ## Steps

        1. Read `project.json`. Walk every row in `r`, and within each row's `s` array collect every shape where `"t": "text"`. Record each shape's `id` and its base string (prefer `txt`; if only `rt` is present, decode the base64 RTF to recover the visible text).
        2. For each target language, ensure a locale entry exists in `ls.l` as `{ "c": "<code>", "l": "<label>" }` (append it if missing — never reorder or remove the first/base entry). Use the language codes the app recognizes, listed below.
        3. For each target language and each text shape, add `ls.o[<code>][<shapeId>] = { "txt": "<translation>" }`. Create the `ls.o[<code>]` object if it doesn't exist.
        4. Write the file back as valid JSON. Do not change `r`, shape positions/sizes, `id`s, or `m`. Only add/modify entries under `ls.l` and `ls.o`.

        ## Translation guidance

        - Keep translations concise — these render inside fixed screenshot layouts, so avoid making strings dramatically longer than the original.
        - Preserve product/brand names, emoji, and any intentional capitalization style.
        - Match the tone of marketing copy (punchy, benefit-led), not literal word-for-word translation.
        - Don't translate placeholder-looking tokens or URLs.

        ## Recognized language codes

        Use these `code` / `label` pairs for `ls.l` entries (BCP-47-style codes the app understands):

        \(localeList)\(schemaSection)
        """
    }

    private static func bundledSchema() -> String? {
        guard let url = Bundle.main.url(forResource: "project-schema", withExtension: "json"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return text
    }
}
