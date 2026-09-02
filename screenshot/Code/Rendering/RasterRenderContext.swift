import SwiftUI

/// Which surface a view is being drawn for.
///
/// `\.isExportRendering` answers the narrower question — offscreen, or live on the canvas — which
/// is the wrong one for any cache whose entries are pixels. A project-card thumbnail rasterizes
/// offscreen exactly like an export, but draws the *editor's* screenshots: downsamples
/// `EditorImagePresentation` has already moved to sRGB. Keyed as one thing, a card render can
/// define an exported PNG's bytes.
nonisolated enum RasterRenderContext: String, Sendable {
    /// Live in the editor.
    case canvas
    /// Rasterized offscreen, but only ever shown on screen — drawn from the editor's images.
    case displayRaster
    /// The bytes we ship, drawn from full-resolution images off disk.
    case export

    /// What a `ViewRasterizer` pass renders as unless a caller scopes it otherwise.
    ///
    /// Not a safe default so much as an honest one: `RowRenderer`'s entry points are shared, so the
    /// export path cannot declare itself without threading a parameter through every one of them.
    /// A caller whose raster ends up on screen must scope itself, the way `ProjectThumbnailService`
    /// does — otherwise it shares export's cache entries.
    @TaskLocal static var current: RasterRenderContext = .export
}

extension EnvironmentValues {
    /// Set by `ViewRasterizer` from `RasterRenderContext.current`; `.canvas` everywhere else.
    @Entry var rasterRenderContext: RasterRenderContext = .canvas
}
