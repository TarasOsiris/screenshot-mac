import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct CanvasHitTestingTests {

    private let unitRect = CGRect(x: 100, y: 100, width: 100, height: 50)

    // MARK: - Unrotated

    @Test func containsPointInsideAnUnrotatedRect() {
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 150, y: 120), rect: unitRect, rotationDegrees: 0, clip: nil))
    }

    @Test func rejectsPointOutsideAnUnrotatedRect() {
        #expect(!CanvasHitTesting.contains(point: CGPoint(x: 250, y: 120), rect: unitRect, rotationDegrees: 0, clip: nil))
    }

    @Test func acceptsPointsExactlyOnTheEdge() {
        // The old bounding-box test was inclusive on every edge; stay inclusive so a click on the
        // border of a shape keeps landing on it.
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 100, y: 100), rect: unitRect, rotationDegrees: 0, clip: nil))
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 200, y: 150), rect: unitRect, rotationDegrees: 0, clip: nil))
    }

    // MARK: - Rotation

    @Test func rotatedShapeMissesItsOwnBoundingBoxCorner() {
        // A square rotated 45° has an empty AABB corner. The bounding-box test reported a hit
        // there; the precise test must not.
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        let corner = CGPoint(x: 2, y: 2)
        #expect(!CanvasHitTesting.contains(point: corner, rect: square, rotationDegrees: 45, clip: nil))
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 50, y: 50), rect: square, rotationDegrees: 45, clip: nil))
    }

    @Test func rotationIsMeasuredAboutTheCentre() {
        // 90° turns the tall rect on its side: a point that was outside is now inside, and vice versa.
        let tall = CGRect(x: 0, y: 0, width: 20, height: 100)
        #expect(!CanvasHitTesting.contains(point: CGPoint(x: 45, y: 50), rect: tall, rotationDegrees: 0, clip: nil))
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 45, y: 50), rect: tall, rotationDegrees: 90, clip: nil))
    }

    @Test func negativeAndOverTurnRotationsBehaveTheSame() {
        let square = CGRect(x: 0, y: 0, width: 100, height: 100)
        let corner = CGPoint(x: 2, y: 2)
        #expect(!CanvasHitTesting.contains(point: corner, rect: square, rotationDegrees: -45, clip: nil))
        #expect(!CanvasHitTesting.contains(point: corner, rect: square, rotationDegrees: 405, clip: nil))
    }

    // MARK: - Clipping

    @Test func clipExcludesPointsOutsideTheColumn() {
        let clip = CGRect(x: 1000, y: 0, width: 1000, height: 2000)
        let spanning = CGRect(x: 600, y: 100, width: 900, height: 100)
        #expect(!CanvasHitTesting.contains(point: CGPoint(x: 650, y: 150), rect: spanning, rotationDegrees: 0, clip: clip))
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 1100, y: 150), rect: spanning, rotationDegrees: 0, clip: clip))
    }

    @Test func clipIsInclusiveOnItsEdges() {
        // The bounding-box path this replaced was inclusive on every edge, so a press exactly on a
        // clipped shape's column boundary must still land on it.
        let clip = CGRect(x: 1000, y: 0, width: 1000, height: 2000)
        let spanning = CGRect(x: 600, y: 100, width: 1500, height: 100)
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 2000, y: 150), rect: spanning, rotationDegrees: 0, clip: clip))
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 1000, y: 150), rect: spanning, rotationDegrees: 0, clip: clip))
        #expect(!CanvasHitTesting.contains(point: CGPoint(x: 2001, y: 150), rect: spanning, rotationDegrees: 0, clip: clip))
    }

    // MARK: - Degenerate

    @Test func zeroSizedShapeIsHitOnlyAtItsPoint() {
        let dot = CGRect(x: 50, y: 50, width: 0, height: 0)
        #expect(CanvasHitTesting.contains(point: CGPoint(x: 50, y: 50), rect: dot, rotationDegrees: 0, clip: nil))
        #expect(!CanvasHitTesting.contains(point: CGPoint(x: 51, y: 50), rect: dot, rotationDegrees: 0, clip: nil))
    }
}
