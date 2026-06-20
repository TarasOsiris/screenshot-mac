import XCTest
import SwiftUI
@testable import Screenshot_Bro

/// Regression: a row background must not bleed through around templates whose
/// override background fully covers them. Stacking the row fill under an opaque
/// override produced a light hairline ring at every template edge (visible at
/// fractional display scales, e.g. iPad pinch zoom).
@MainActor
final class RowBackgroundOverrideBleedTests: XCTestCase {
    func testOpaqueOverrideHidesRowBackgroundAtTileEdges() throws {
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
            let renderer = ImageRenderer(content: RowPreviewView(state: state, row: state.rows[0], zoom: zoom))
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else {
                XCTFail("render failed"); return
            }

            var seamPixels = 0
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let c = rep.colorAt(x: x, y: y) else { continue }
                    if c.alphaComponent > 0.2 && c.redComponent > 0.1 {
                        seamPixels += 1
                    }
                }
            }
            XCTAssertEqual(seamPixels, 0, "row background bleeds through at zoom \(zoom)")
        }
    }
}
