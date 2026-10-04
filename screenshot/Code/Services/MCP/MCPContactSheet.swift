#if os(macOS)
import AppKit

/// A grid of up to 20 proposed screenshots, so an agent can see a sync preview at a glance.
enum MCPContactSheet {
    static func png(plan: ASCScreenshotSyncPlan) -> Data? {
        let previews = plan.sets.flatMap(\.proposedAssets).compactMap { $0.localAsset?.previewData }.prefix(20)
        let images = previews.compactMap { NSImage(data: $0) }
        guard !images.isEmpty else { return nil }
        let columns = min(5, images.count)
        let rows = Int(ceil(Double(images.count) / Double(columns)))
        let cell = CGSize(width: 150, height: 210)
        let canvasSize = CGSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(canvasSize.width),
            pixelsHigh: Int(canvasSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: canvasSize)).fill()
        for (index, image) in images.enumerated() {
            let column = index % columns
            let row = index / columns
            let cellRect = CGRect(
                x: CGFloat(column) * cell.width + 8,
                y: canvasSize.height - CGFloat(row + 1) * cell.height + 8,
                width: cell.width - 16,
                height: cell.height - 16
            )
            let scale = min(cellRect.width / image.size.width, cellRect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let rect = CGRect(x: cellRect.midX - size.width / 2, y: cellRect.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif
