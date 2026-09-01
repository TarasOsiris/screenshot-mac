import CoreGraphics
@testable import Screenshot_Bro
import Testing

@MainActor
struct CanvasHoverLayerTests {

    private let row = ScreenshotRow(
        templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
        templateWidth: 1_000,
        templateHeight: 2_000
    )

    @Test func unclippedShapeHoverUsesTheWholeCanvasAtVisualScale() {
        let shape = CanvasShapeModel(
            type: .rectangle,
            x: 1_100,
            y: 100,
            width: 100,
            height: 100
        )

        let bounds = CanvasHoverLayer.visibleBounds(for: shape, in: row, visualScale: 0.25)

        #expect(bounds == CGRect(x: 0, y: 0, width: 750, height: 500))
    }

    @Test func clippedShapeHoverUsesItsNonFirstTemplateAtVisualScale() {
        var shape = CanvasShapeModel(
            type: .rectangle,
            x: 1_100,
            y: 100,
            width: 100,
            height: 100
        )
        shape.clipToTemplate = true

        let bounds = CanvasHoverLayer.visibleBounds(for: shape, in: row, visualScale: 0.25)

        #expect(bounds == CGRect(x: 250, y: 0, width: 250, height: 500))
    }
}
