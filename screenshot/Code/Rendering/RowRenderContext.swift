import SwiftUI

/// The slice of the open document a renderer needs. `AppState` conforms; tests and upload
/// services can take this instead of the whole app state.
@MainActor
protocol RowRenderSource: AnyObject {
    var localeState: LocaleState { get }
    var availableFontFamilySet: Set<String> { get }
    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String>
    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage]
    /// Resolves this source's custom fonts for the duration of one **synchronous** render.
    func withResolvedFonts<R>(_ body: () -> R) -> R
}

extension RowRenderSource {
    /// The process font registry already describes the open document, so the open document needs
    /// no scope. Only a source reading a project the editor does *not* have open overrides this.
    func withResolvedFonts<R>(_ body: () -> R) -> R { body() }
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
    /// Captured from the source so every render through this context resolves the same fonts.
    /// Only the synchronous renders are wrapped — `showcaseImage` is async and editor-only, and a
    /// scoped registry swap must not be held across a suspension point.
    private let resolveFonts: (() -> NSImage) -> NSImage
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
    /// Resources disk *did* produce that cannot draw — zero-sized, or with no representation a
    /// `CGImage` can come from. They composite to the same hole as a missing file while passing
    /// every presence check, which is the shape that shipped 112 blank store screenshots.
    let unusableImageFileNames: [String]

    /// Everything referenced that will not appear in the output, whichever way it failed. Refuse
    /// on this rather than on `missingImageFileNames` alone.
    var unrenderableImageFileNames: [String] { (missingImageFileNames + unusableImageFileNames).sorted() }

    init(
        row: ScreenshotRow,
        images: [String: NSImage],
        localeCode: String?,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>,
        displayScale: CGFloat = 1.0,
        label: String,
        missingImageFileNames: [String] = [],
        unusableImageFileNames: [String] = [],
        resolveFonts: @escaping (() -> NSImage) -> NSImage = { $0() }
    ) {
        self.resolveFonts = resolveFonts
        self.row = row
        self.images = images
        self.localeCode = localeCode
        self.localeState = localeState
        self.availableFontFamilies = availableFontFamilies
        self.displayScale = displayScale
        self.label = label
        self.missingImageFileNames = missingImageFileNames
        self.unusableImageFileNames = unusableImageFileNames
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
        missingImageFileNames: [String],
        unusableImageFileNames: [String]
    ) {
        self.resolveFonts = other.resolveFonts
        self.row = other.row
        self.images = images
        self.localeCode = localeCode
        self.localeState = other.localeState
        self.availableFontFamilies = other.availableFontFamilies
        self.displayScale = other.displayScale
        self.label = other.label
        self.precomposedRowBackground = other.precomposedRowBackground
        self.missingImageFileNames = missingImageFileNames
        self.unusableImageFileNames = unusableImageFileNames
    }

    /// The same row and settings against another locale's resolved images, reusing the already
    /// precomposed background. Replaces the hand-managed `var rowBackground` + `if index == 0`.
    ///
    /// The two report arrays are required rather than defaulted: defaulting them let a caller
    /// hand back a context claiming a clean bill of health, which is the shape of bug the reports
    /// exist to catch.
    func withLocale(
        _ localeCode: String,
        images: [String: NSImage],
        missingImageFileNames: [String],
        unusableImageFileNames: [String]
    ) -> RowRenderContext {
        RowRenderContext(
            copying: self,
            localeCode: localeCode,
            images: images,
            missingImageFileNames: missingImageFileNames,
            unusableImageFileNames: unusableImageFileNames
        )
    }

    var templateIndices: Range<Int> { row.templates.indices }

    func templateImage(at index: Int) -> NSImage {
        resolveFonts {
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
    }

    func templateData(at index: Int, format: ExportImageFormat) -> Data? {
        ExportImageEncoder.encode(templateImage(at: index), format: format)
    }

    func rowImage() -> NSImage {
        resolveFonts {
            RowRenderer.renderRowImage(
                row: row,
                screenshotImages: images,
                localeCode: localeCode,
                localeState: localeState,
                availableFontFamilies: availableFontFamilies,
                displayScale: displayScale
            )
        }
    }

    func showcaseImage(config: ShowcaseExportConfig) async -> NSImage {
        await RowRenderer.renderShowcaseRowImage(
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
        // Both lists have to describe the *merged* dictionary: a seed that replaces an undrawable
        // disk image renders fine, and reporting it would now abort an upload rather than just
        // colour a log line.
        let missing = fileNames.subtracting(images.keys).sorted()
        let unusable = fileNames.filter { name in
            guard let image = images[name] else { return false }   // absent is `missing`, not unusable
            return !image.canDraw
        }.sorted()

        if let previous, previous.row.id == row.id {
            return previous.withLocale(
                localeCode, images: images,
                missingImageFileNames: missing, unusableImageFileNames: unusable
            )
        }
        return RowRenderContext(
            row: row,
            images: images,
            localeCode: localeCode,
            localeState: source.localeState,
            availableFontFamilies: source.availableFontFamilySet,
            displayScale: displayScale,
            label: label,
            missingImageFileNames: missing,
            unusableImageFileNames: unusable,
            resolveFonts: { render in source.withResolvedFonts(render) }
        )
    }
}
