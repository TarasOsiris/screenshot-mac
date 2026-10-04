import CoreGraphics
@testable import Screenshot_Bro
import Testing

@MainActor
struct RichTextFormatBarPlacementTests {

    private let barSize = CGSize(width: 100, height: 40)
    private let inset: CGFloat = 4
    private let containerSize = CGSize(width: 800, height: 600)

    private func center(anchor: CGPoint, origin: CGPoint = .zero, container: CGSize? = nil) -> CGPoint {
        RichTextFormatBarPlacement.clampedCenter(
            anchor: anchor,
            containerOrigin: origin,
            containerSize: container ?? containerSize,
            barSize: barSize,
            inset: inset
        )
    }

    @Test func sitsHalfABarAboveTheAnchorWhenThereIsRoom() {
        #expect(center(anchor: CGPoint(x: 400, y: 300)) == CGPoint(x: 400, y: 280))
    }

    @Test func convertsTheGlobalAnchorIntoContainerSpace() {
        let result = center(anchor: CGPoint(x: 450, y: 370), origin: CGPoint(x: 50, y: 70))
        #expect(result == CGPoint(x: 400, y: 280))
    }

    @Test func clampsToTheLeadingAndTopEdges() {
        #expect(center(anchor: CGPoint(x: 10, y: 5)) == CGPoint(x: 54, y: 24))
    }

    @Test func clampsToTheTrailingAndBottomEdges() {
        #expect(center(anchor: CGPoint(x: 2_000, y: 2_000)) == CGPoint(x: 746, y: 576))
    }

    @Test func farEdgeWinsWhenTheContainerIsNarrowerThanTheBar() {
        let result = center(anchor: CGPoint(x: 30, y: 300), container: CGSize(width: 60, height: 600))
        #expect(result == CGPoint(x: 6, y: 280))
    }
}
