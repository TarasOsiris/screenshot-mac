import Foundation

/// Builds one prompt an external agent can follow, through the in-app MCP server, to make every
/// overflowing text fit — the copyable counterpart of the upload wizard's overflow warnings.
enum TextOverflowPromptService {
    struct RowOverflows {
        let row: ScreenshotRow
        let overflows: [TextOverflow]
    }

    static func prompt(projectId: UUID, rows: [RowOverflows], localeState: LocaleState) -> String {
        let base = localeState.baseLocaleCode
        let sections = rows.map { section(for: $0, base: base, localeState: localeState) }.joined(separator: "\n\n")

        return """
        Some text in a **Screenshot Bro** project doesn't fit its text box in some languages, so its last lines are cut off in the exported App Store / Google Play screenshots. Fix every case below using the Screenshot Bro MCP server (`screenshot-bro`). If its tools aren't available, ask me to enable it in Screenshot Bro ▸ Settings ▸ Automation.

        Project: `\(projectId.uuidString)`

        ## Text that overflows

        \(sections)

        ## Steps

        1. Call `switch_project` with the project id above, unless it is already the open project.
        2. Call `get_project` once. Each text shape lists its `translations` and `text_overflow_locales` — the locales whose text is cut off right now.
        3. Check every listed translation actually says what its base text says. A translation copied from another shape is a different headline; retranslate it in every locale of that shape, not just the overflowing ones.
        4. Prefer a shorter translation: `set_translation` with `shape_id`, `locale_code` and the new `text`. Keep the meaning and the punchy marketing tone, stay in that language, and keep line breaks only where they help.
        5. Only when no natural shorter phrasing exists, call `update_shape` with `shape_id` and `shrink_to_fit: true` — it shrinks the font in that box for every locale that needs it. Don't resize or move the box; that changes the layout in every language.
        6. Call `get_project` again and repeat until no shape has `text_overflow_locales`. Then `render_preview` (`project_id`, `row_id`, `locale`) a few fixed rows to confirm they read well. Don't change the base (`\(base)`) text — if the base locale itself is listed, use `shrink_to_fit` for it rather than rewriting it.
        """
    }

    private static func section(for entry: RowOverflows, base: String, localeState: LocaleState) -> String {
        let rowName = entry.row.label.isEmpty ? "Row" : "Row \(quoted(entry.row.label))"
        let shapes = entry.overflows.map { overflow in
            let baseText = resolvedText(overflow.shape, localeCode: base, localeState: localeState)
            let locales = overflow.localeCodes.map { code in
                "  - `\(code)`: \(quoted(resolvedText(overflow.shape, localeCode: code, localeState: localeState)))"
            }
            return (["- Shape `\(overflow.shape.id.uuidString)` — base (`\(base)`): \(quoted(baseText))"] + locales)
                .joined(separator: "\n")
        }
        return (["### \(rowName) — `\(entry.row.id.uuidString)`"] + shapes).joined(separator: "\n")
    }

    private static func resolvedText(_ shape: CanvasShapeModel, localeCode: String, localeState: LocaleState) -> String {
        LocaleService.resolveShape(shape, localeCode: localeCode, localeState: localeState).text ?? ""
    }

    /// JSON string syntax, so a quote or line break inside the text can't end it early.
    private static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }
}
