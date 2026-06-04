import SwiftUI

struct RowContextMenuPreview: View {
    let state: AppState
    let row: ScreenshotRow
    @Environment(\.displayScale) var screenScale

    let maxPreviewWidth: CGFloat = 360
    let maxPreviewHeight: CGFloat = 240
    let tileGap: CGFloat = 12

    var baseWidth: CGFloat {
        let count = CGFloat(row.templates.count)
        return row.displayWidth(zoom: 1.0) * count + tileGap * max(0, count - 1)
    }

    var baseHeight: CGFloat {
        row.displayHeight(zoom: 1.0)
    }

    var previewZoom: CGFloat {
        min(maxPreviewWidth / max(baseWidth, 1), maxPreviewHeight / max(baseHeight, 1), 1)
    }

    var body: some View {
        // Bake the preview to a flat image up front. The system renders context-menu
        // previews in an offscreen pass where the row's SceneKit-backed device frames
        // re-render incorrectly (smaller, inner-screen only); a pre-rasterized image —
        // produced by a controlled `ImageRenderer` pass — renders devices correctly and
        // isn't re-evaluated during the lift. Falls back to the live view if rendering fails.
        let renderer = ImageRenderer(content: RowPreviewView(state: state, row: row, zoom: previewZoom))
        renderer.scale = max(1, screenScale)
        #if os(macOS)
        let baked = renderer.nsImage
        #else
        let baked = renderer.uiImage
        #endif

        return Group {
            if let baked {
                Image(nsImage: baked)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: baseWidth * previewZoom, height: baseHeight * previewZoom)
            } else {
                RowPreviewView(state: state, row: row, zoom: previewZoom)
            }
        }
        .contextMenuPreviewCard()
    }
}
