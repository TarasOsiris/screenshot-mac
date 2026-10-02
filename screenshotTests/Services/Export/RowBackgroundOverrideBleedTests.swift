import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Regression: a row background must not bleed through around templates whose
/// override background fully covers them. Stacking the row fill under an opaque
/// override produced a light hairline ring at every template edge (visible at
/// fractional display scales, e.g. iPad pinch zoom).
@Suite(.serialized)
@MainActor
struct RowBackgroundOverrideBleedTests {

    // One test over both zooms rather than `@Test(arguments:)`: `makeTestState` mutates the
    // process-global SCREENSHOT_DATA_DIR, so parallel cases would race over the same root.
    @Test func opaqueOverrideHidesRowBackgroundAtTileEdges() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }

        var row = state.rows[0]
        row.backgroundStyle = .color
        row.backgroundColorData = CodableColor(Color.white)
        for i in row.templates.indices {
            row.templates[i].overrideBackground = true
            row.templates[i].backgroundStyle = .color
            row.templates[i].backgroundColor = CodableColor(Color.black)
        }
        row.shapes = []
        state.rows[0] = row

        for zoom in [1.0, 1.13] as [CGFloat] {
            let renderer = ImageRenderer(content: RowPreviewView(
                row: state.rows[0],
                zoom: zoom,
                localeState: state.localeState,
                screenshotImages: state.screenshotImages,
                availableFontFamilies: state.availableFontFamilySet
            ))
            renderer.scale = 2
            let image = try #require(renderer.nsImage, "render failed")
            let tiff = try #require(image.tiffRepresentation)
            let rep = try #require(NSBitmapImageRep(data: tiff))

            var seamPixels = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y) else { continue }
                    if c.alphaComponent > 0.2 && c.redComponent > 0.1 {
                        seamPixels += 1
                    }
                }
            }
            #expect(seamPixels == 0, "row background bleeds through at zoom \(zoom)")
        }
    }

    /// Regression: an aspect-filled override image overflowed its slot in the editor and painted
    /// over the neighbouring templates.
    @Test func fillImageOverrideStaysInsideItsTemplate() throws {
        var row = ScreenshotRow(templates: (0..<3).map { _ in ScreenshotTemplate() }, templateWidth: 1242, templateHeight: 2688)
        row.backgroundStyle = .color
        row.backgroundColorData = CodableColor(Color.red)
        row.templates[1].overrideBackground = true
        row.templates[1].backgroundStyle = .image
        row.templates[1].backgroundImageConfig = BackgroundImageConfig(fileName: "wide.png", fillMode: .fill)

        let wide = NSImage(size: NSSize(width: 4000, height: 100))
        wide.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 4000, height: 100).fill()
        wide.unlockFocus()

        let scale: CGFloat = 0.1
        let slotWidth = row.templateWidth * scale
        let height = row.templateHeight * scale
        let image = RowRenderer.renderViewToImage(
            RowCanvasBackgroundView(row: row, screenshotImages: ["wide.png": wide], displayScale: scale, blurRadius: 0),
            width: slotWidth * 3,
            height: height,
            label: "override fill bleed"
        )
        let tiff = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        let pxSlot = rep.pixelsWide / 3
        let midY = rep.pixelsHigh / 2

        func color(_ x: Int) throws -> NSColor {
            try #require(rep.colorAt(x: x, y: midY)?.usingColorSpace(.sRGB))
        }
        for x in [pxSlot / 2, pxSlot - 3, 2 * pxSlot + 3, 2 * pxSlot + pxSlot / 2] {
            let c = try color(x)
            #expect(c.redComponent > c.blueComponent + 0.3, "override image bled into neighbour at x=\(x): \(c)")
        }
        let middle = try color(pxSlot + pxSlot / 2)
        #expect(middle.blueComponent > middle.redComponent + 0.3, "override image missing from its own slot: \(middle)")
    }
}
