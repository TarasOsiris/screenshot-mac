import Foundation

/// A project's editable content — the rows and the locale state — as a plain value.
///
/// It exists so the same editing verbs can be applied to a project whether or not the editor has
/// it open. `AppState` holds the open document and adds undo, autosave, selection and the rest;
/// this is the part that has none of those concerns and is therefore reusable.
///
/// Deliberately **not** `Codable`: `ProjectData` remains the on-disk DTO with its short coding
/// keys, so nothing about the persisted shape changes. Bridge with `init(_:)` / `projectData(name:)`.
/// Not `nonisolated`: `ScreenshotRow`'s synthesized `Equatable` is main-actor isolated, and every
/// caller (the editor, the renderers, the MCP executor) is on the main actor anyway.
struct ProjectDocument: Equatable {
    var rows: [ScreenshotRow]
    var localeState: LocaleState

    init(rows: [ScreenshotRow], localeState: LocaleState = .default) {
        self.rows = rows
        self.localeState = localeState
    }

    init(_ data: ProjectData) {
        self.rows = data.rows
        self.localeState = data.localeState ?? .default
    }

    func projectData(name: String?) -> ProjectData {
        ProjectData(rows: rows, localeState: localeState, name: name)
    }
}

// MARK: - Referenced image resources

extension ProjectDocument {

    /// The one traversal: rows in order, then each row's templates and shapes, then the locale
    /// overrides (keyed by translation key, not shape id, so they can't be interleaved).
    /// `activeBackgroundsOnly` drops background images whose style is switched off — see
    /// `ScreenshotRow.backgroundImageFileName(activeOnly:)`.
    ///
    /// Ordered rather than a `Set` because `loadScreenshotImages` decodes in batches and a large
    /// project should fill in from the top row down; the `Set` callers just wrap the result. Two
    /// walks would mean a new image-bearing property could be added to one and not the other.
    static func orderedReferencedImageFileNames(
        rows targetRows: [ScreenshotRow],
        localeOverrides: [String: [String: ShapeLocaleOverride]],
        activeBackgroundsOnly: Bool = false
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        func append(_ fileName: String?) {
            guard let fileName, seen.insert(fileName).inserted else { return }
            ordered.append(fileName)
        }
        for row in targetRows {
            append(row.backgroundImageFileName(activeOnly: activeBackgroundsOnly))
            for template in row.templates {
                append(template.backgroundImageFileName(activeOnly: activeBackgroundsOnly))
            }
            for shape in row.shapes {
                for fileName in shape.allImageFileNames { append(fileName) }
            }
        }
        for shapeOverrides in localeOverrides.values {
            for override in shapeOverrides.values { append(override.overrideImageFileName) }
        }
        return ordered
    }

    static func referencedImageFileNames(
        rows targetRows: [ScreenshotRow],
        localeOverrides: [String: [String: ShapeLocaleOverride]],
        activeBackgroundsOnly: Bool = false
    ) -> Set<String> {
        Set(orderedReferencedImageFileNames(
            rows: targetRows,
            localeOverrides: localeOverrides,
            activeBackgroundsOnly: activeBackgroundsOnly
        ))
    }

    /// Image filenames needed for the editor (base shapes + active locale overrides only),
    /// in document order.
    func editorReferencedImageFileNames() -> [String] {
        let activeCode = localeState.activeLocaleCode
        let activeOverrides = localeState.overrides[activeCode].map { [activeCode: $0] } ?? [:]
        return Self.orderedReferencedImageFileNames(rows: rows, localeOverrides: activeOverrides)
    }

    /// Every referenced filename in a single pass (for batch cleanup).
    func allReferencedImageFileNames() -> Set<String> {
        Self.referencedImageFileNames(rows: rows, localeOverrides: localeState.overrides)
    }

    /// Image filenames for a specific row and locale (for per-row export). Render path, so
    /// inactive background configs are excluded: they draw nothing, and counting them would
    /// let a stale reference report itself as a missing resource and abort an upload.
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        let localeOverrides = localeState.overrides[localeCode].map { [localeCode: $0] } ?? [:]
        return Self.referencedImageFileNames(rows: [row], localeOverrides: localeOverrides, activeBackgroundsOnly: true)
    }
}
