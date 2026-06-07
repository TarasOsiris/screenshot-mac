import SwiftUI

/// Read-only "App Store" preview of a row. Each template is rendered as its own
/// rounded-corner tile separated by a visible gap; shapes are non-interactive.
/// The view reuses the editor's background + shape layers so what you see here
/// is the same SwiftUI render as the editor (just sliced and clipped).
struct RowPreviewView: View {
    let state: AppState
    let row: ScreenshotRow
    let zoom: CGFloat

    // Zoom is folded into the render scale (no `.scaleEffect`) — scaling an
    // already-clipped tile magnifies the antialiased clip edge, bleeding content
    // past the rounded corners.
    private var displayScale: CGFloat { row.displayScale(zoom: zoom) }
    private var displayTemplateWidth: CGFloat { row.displayWidth(zoom: zoom) }
    private var displayTemplateHeight: CGFloat { row.displayHeight(zoom: zoom) }
    /// Matches `ShowcaseExportConfig.cornerRadiusPercent` default so the in-editor preview
    /// and the showcase export share the same tile look.
    private var tileCornerRadius: CGFloat {
        displayTemplateHeight * CGFloat(ShowcaseExportConfig().cornerRadiusPercent / 100)
    }
    private var tileGap: CGFloat { UIMetrics.Preview.tileGap * zoom }

    var body: some View {
        let resolvedShapes = LocaleService.resolveShapes(
            row.activeShapes,
            localeState: state.localeState
        )
        // Precompute each template's visible (locale-resolved) shapes once per
        // render instead of rebuilding the id set + filter inside every tile's
        // view builder. Filtering `resolvedShapes` preserves z-order.
        let visiblePerTemplate: [[CanvasShapeModel]] = row.templates.indices.map { index in
            let visibleIds = Set(row.visibleShapes(forTemplateAt: index).map(\.id))
            return resolvedShapes.filter { visibleIds.contains($0.id) }
        }

        HStack(alignment: .top, spacing: tileGap) {
            ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, _ in
                tile(at: index, visibleShapes: visiblePerTemplate[index])
            }
        }
        .frame(
            width: rowDisplayWidthWithGaps,
            height: displayTemplateHeight,
            alignment: .topLeading
        )
    }

    private var rowDisplayWidthWithGaps: CGFloat {
        let n = CGFloat(row.templates.count)
        return displayTemplateWidth * n + tileGap * max(0, n - 1)
    }

    @ViewBuilder
    private func tile(at index: Int, visibleShapes visible: [CanvasShapeModel]) -> some View {
        let offsetX = -CGFloat(index) * displayTemplateWidth

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
            availableFontFamilies: state.availableFontFamilySet
        )
    }
}
