import SwiftUI

/// Read-only "App Store" preview of a row. Each template is rendered as its own
/// rounded-corner tile separated by a visible gap; shapes are non-interactive.
/// The view reuses the editor's background + shape layers so what you see here
/// is the same SwiftUI render as the editor (just sliced and clipped).
struct RowPreviewView: View {
    let state: AppState
    let row: ScreenshotRow
    let zoom: CGFloat

    private var displayScale: CGFloat { row.displayScale(zoom: 1.0) }
    private var displayTemplateWidth: CGFloat { row.displayWidth(zoom: 1.0) }
    private var displayTemplateHeight: CGFloat { row.displayHeight(zoom: 1.0) }
    /// Matches `ShowcaseExportConfig.cornerRadiusPercent` default so the in-editor preview
    /// and the showcase export share the same tile look.
    private var tileCornerRadius: CGFloat {
        displayTemplateHeight * CGFloat(ShowcaseExportConfig().cornerRadiusPercent / 100)
    }
    private var tileGap: CGFloat { 12 }

    var body: some View {
        let resolvedShapes = LocaleService.resolveShapes(
            row.activeShapes,
            localeState: state.localeState
        )

        HStack(alignment: .top, spacing: tileGap) {
            ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, _ in
                tile(at: index, resolvedShapes: resolvedShapes)
            }
        }
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(
            width: rowDisplayWidthWithGaps * zoom,
            height: displayTemplateHeight * zoom,
            alignment: .topLeading
        )
    }

    private var rowDisplayWidthWithGaps: CGFloat {
        let n = CGFloat(row.templates.count)
        return displayTemplateWidth * n + tileGap * max(0, n - 1)
    }

    @ViewBuilder
    private func tile(at index: Int, resolvedShapes: [CanvasShapeModel]) -> some View {
        let offsetX = -CGFloat(index) * displayTemplateWidth
        // Reuse the same visibility predicate the editor's per-template logic
        // uses; filter the locale-resolved set by id to avoid constructing
        // shapes that the parent tile clip would hide anyway.
        let visibleIds = Set(row.visibleShapes(forTemplateAt: index).map(\.id))
        let visible = resolvedShapes.filter { visibleIds.contains($0.id) }

        ZStack(alignment: .topLeading) {
            // Live (non-rasterized) background so we don't pay the per-tile cost of
            // `EditorRasterizedBackgroundView`'s blur cache + render task.
            RowCanvasBackgroundView(
                row: row,
                screenshotImages: state.screenshotImages,
                displayScale: displayScale,
                blurRadius: row.backgroundBlur * displayScale
            )
            .frame(
                width: displayTemplateWidth * CGFloat(row.templates.count),
                height: displayTemplateHeight,
                alignment: .topLeading
            )
            .offset(x: offsetX)

            RowCanvasShapeLayerView(
                row: row,
                shapes: visible,
                displayScale: displayScale
            ) { shape, clipRect in
                previewShape(shape, clipRect: clipRect)
            }
            .offset(x: offsetX)
        }
        .frame(width: displayTemplateWidth, height: displayTemplateHeight, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: tileCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func previewShape(_ shape: CanvasShapeModel, clipRect: CGRect?) -> some View {
        CanvasShapeView(
            shape: shape,
            displayScale: displayScale,
            zoom: 1.0,
            isSelected: false,
            screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
            fillImage: shape.fillImageConfig?.fileName.flatMap { state.screenshotImages[$0] },
            defaultDeviceBodyColor: row.defaultDeviceBodyColor,
            deviceModelRenderingMode: .snapshot,
            clipBounds: clipRect,
            showsEditorHelpers: false,
            onSelect: {},
            onUpdate: { _ in },
            onDelete: {},
            availableFontFamilies: state.availableFontFamilySet
        )
    }
}
