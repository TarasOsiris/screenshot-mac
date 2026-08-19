import SwiftUI

/// The slice of the open document a renderer needs. `AppState` conforms; tests and upload
/// services can take this instead of the whole app state.
@MainActor
protocol RowRenderSource: AnyObject {
    var localeState: LocaleState { get }
    var availableFontFamilySet: Set<String> { get }
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String>
    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage]
}

/// Everything the row renderers need beyond a template index, resolved once per (row, locale).
///
/// It exists because the "resolve images, precompose the row background, then loop
/// `renderSingleTemplateImage`" preamble was hand-written at eight call sites, and most of them
/// dropped `availableFontFamilies` along the way — which exported custom-font text in the system
/// face. `availableFontFamilies` therefore has no default here: supplying it is the point.
@MainActor
struct RowRenderContext {
    let row: ScreenshotRow
    let images: [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>
    let displayScale: CGFloat
    let label: String
    /// nil unless `row.backgroundBlur > 0` — blur has to sample across template boundaries, so
    /// only then is the oversized strip worth building. Locale-independent, so `withLocale`
    /// carries it forward rather than re-rendering it per locale.
    let precomposedRowBackground: NSImage?
    /// Resources the model references that disk couldn't produce. Rendering degrades silently to
    /// a hole, so upload paths should refuse a context with a non-empty set.
    let missingImageFileNames: [String]

    init(
        row: ScreenshotRow,
        images: [String: NSImage],
        localeCode: String?,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>,
        displayScale: CGFloat = 1.0,
        label: String,
        missingImageFileNames: [String] = []
    ) {
        self.row = row
        self.images = images
        self.localeCode = localeCode
        self.localeState = localeState
        self.availableFontFamilies = availableFontFamilies
        self.displayScale = displayScale
        self.label = label
        self.missingImageFileNames = missingImageFileNames
        self.precomposedRowBackground = RowRenderer.precomposedRowBackgroundIfNeeded(
            row: row,
            screenshotImages: images,
            displayScale: displayScale,
            labelPrefix: label
        )
    }

    private init(
        copying other: RowRenderContext,
        localeCode: String,
        images: [String: NSImage],
        missingImageFileNames: [String]
    ) {
        self.row = other.row
        self.images = images
        self.localeCode = localeCode
        self.localeState = other.localeState
        self.availableFontFamilies = other.availableFontFamilies
        self.displayScale = other.displayScale
        self.label = other.label
        self.precomposedRowBackground = other.precomposedRowBackground
        self.missingImageFileNames = missingImageFileNames
    }

    /// The same row and settings against another locale's resolved images, reusing the already
    /// precomposed background. Replaces the hand-managed `var rowBackground` + `if index == 0`.
    func withLocale(
        _ localeCode: String,
        images: [String: NSImage],
        missingImageFileNames: [String] = []
    ) -> RowRenderContext {
        RowRenderContext(
            copying: self,
            localeCode: localeCode,
            images: images,
            missingImageFileNames: missingImageFileNames
        )
    }

    var templateIndices: Range<Int> { row.templates.indices }

    func templateImage(at index: Int) -> NSImage {
        RowRenderer.renderSingleTemplateImage(
            index: index,
            row: row,
            screenshotImages: images,
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies,
            displayScale: displayScale,
            preRenderedRowBackground: precomposedRowBackground
        )
    }

    func templateData(at index: Int, format: ExportImageFormat) -> Data? {
        ExportImageEncoder.encode(templateImage(at: index), format: format)
    }

    func rowImage() -> NSImage {
        RowRenderer.renderRowImage(
            row: row,
            screenshotImages: images,
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies,
            displayScale: displayScale
        )
    }

    func showcaseImage(config: ShowcaseExportConfig) -> NSImage {
        RowRenderer.renderShowcaseRowImage(
            row: row,
            screenshotImages: images,
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies,
            config: config
        )
    }

    /// Renders every template in order. Owns the per-iteration `await Task.yield()`: without it a
    /// long row renders as one uninterrupted main-actor job, which is the shape of the multi-second
    /// hang that shipped in 4.0 (108) (Sentry SCREENSHOT-BRO-2/-3).
    func forEachTemplate(_ body: (_ index: Int, _ image: NSImage) async throws -> Void) async rethrows {
        for index in templateIndices {
            try await body(index, templateImage(at: index))
            await Task.yield()
        }
    }
}

extension RowRenderContext {
    /// The image-loading preamble, once. Resolves `row`'s resources for `localeCode` through
    /// `source` (sharing `cache` across rows and locales) and builds the context; pass the
    /// previous context as `reusing` to keep its precomposed background when the row is the same.
    /// `seedImages` carries in-memory-only resources (the showcase sheet's transient background)
    /// that disk loading can never produce — the cache is read-through, not a seed.
    static func load(
        row: ScreenshotRow,
        localeCode: String,
        from source: some RowRenderSource,
        displayScale: CGFloat = 1.0,
        label: String,
        cache: inout [String: NSImage],
        seedImages: [String: NSImage] = [:],
        reusing previous: RowRenderContext? = nil
    ) -> RowRenderContext {
        let fileNames = source.referencedImageFileNames(forRow: row, localeCode: localeCode)
        var images = source.loadFullResolutionImages(fileNames: fileNames, cache: &cache)
        images.merge(seedImages) { _, seed in seed }
        let missing = fileNames.subtracting(images.keys).sorted()

        if let previous, previous.row.id == row.id {
            return previous.withLocale(localeCode, images: images, missingImageFileNames: missing)
        }
        return RowRenderContext(
            row: row,
            images: images,
            localeCode: localeCode,
            localeState: source.localeState,
            availableFontFamilies: source.availableFontFamilySet,
            displayScale: displayScale,
            label: label,
            missingImageFileNames: missing
        )
    }
}
