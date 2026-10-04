import SwiftUI

struct ShowcasePreviewColumn: View {
    let rows: [ScreenshotRow]
    let config: ShowcaseExportConfig
    let transientBackgroundImages: [String: NSImage]
    let loadImages: (ScreenshotRow) -> [String: NSImage]
    let localeCode: String?
    let localeState: LocaleState
    let availableFontFamilies: Set<String>

    var body: some View {
        if rows.isEmpty {
            emptyPreview
        } else {
            GeometryReader { geo in
                let inset = ShowcaseExportSheetMetrics.previewContentInset
                let contentWidth = max(geo.size.width - inset * 2, 80)
                if rows.count == 1 {
                    singleRowPreview(row: rows[0], geo: geo, inset: inset, contentWidth: contentWidth)
                } else {
                    multiRowPreview(contentWidth: contentWidth, inset: inset)
                }
            }
        }
    }

    private func singleRowPreview(
        row: ScreenshotRow,
        geo: GeometryProxy,
        inset: CGFloat,
        contentWidth: CGFloat
    ) -> some View {
        let contentHeight = max(geo.size.height - inset * 2, 80)
        return ShowcaseRowPreview(
            row: row,
            config: config,
            transientBackgroundImages: transientBackgroundImages,
            containerSize: CGSize(width: contentWidth, height: contentHeight),
            loadImages: { loadImages(row) },
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
        .padding(inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func multiRowPreview(contentWidth: CGFloat, inset: CGFloat) -> some View {
        let layout = ShowcasePreviewGridLayout(contentWidth: contentWidth, rowCount: rows.count)
        return ScrollView(.vertical) {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 80), spacing: layout.spacing, alignment: .top),
                    count: layout.columnCount
                ),
                spacing: layout.spacing
            ) {
                ForEach(rows) { row in
                    ShowcaseRowPreview(
                        row: row,
                        config: config,
                        transientBackgroundImages: transientBackgroundImages,
                        containerSize: CGSize(width: layout.columnWidth, height: .infinity),
                        loadImages: { loadImages(row) },
                        localeCode: localeCode,
                        localeState: localeState,
                        availableFontFamilies: availableFontFamilies
                    )
                    .id(row.id)
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity)
        }
    }

    private var emptyPreview: some View {
        ContentUnavailableView(
            "No rows selected",
            systemImage: "rectangle.stack.badge.minus",
            description: Text("Select at least one row to preview and export.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShowcasePreviewGridLayout {
    let contentWidth: CGFloat
    let rowCount: Int

    var spacing: CGFloat {
        ShowcaseExportSheetMetrics.previewItemSpacing
    }

    var columnCount: Int {
        contentWidth >= ShowcaseExportSheetMetrics.gridTwoColumnThreshold && rowCount >= 2 ? 2 : 1
    }

    var columnWidth: CGFloat {
        columnCount == 2 ? max((contentWidth - spacing) / 2, 80) : contentWidth
    }
}
