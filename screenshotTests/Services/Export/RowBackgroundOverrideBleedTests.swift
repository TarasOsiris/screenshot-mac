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
}
