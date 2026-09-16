import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct ResizeGeometryTests {
    private func device(rotation: Double = 0) -> CanvasShapeModel {
        var shape = CanvasShapeModel(type: .device, x: 100, y: 200, width: 300, height: 650)
        shape.deviceCategory = .iphone
        shape.rotation = rotation
        return shape
    }

    private func rectangle() -> CanvasShapeModel {
        CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 650)
    }

    /// Continuity is the property under test, so sweep the translation and look at the largest
    /// single-step change rather than sampling a few values.
    private func largestWidthStep(_ shape: CanvasShapeModel, _ translations: [CGSize]) -> (step: CGFloat, last: CGFloat) {
        var previous: CGFloat?
        var largest: CGFloat = 0
        for translation in translations {
            let state = ResizeGeometry.resize(
                shape: shape,
                edge: .bottomRight,
                translation: translation,
                lockAspectRatio: true
            )
            if let previous { largest = max(largest, abs(state.newW - previous)) }
            previous = state.newW
        }
        return (largest, previous ?? 0)
    }

    /// The bug this was written for. A device always locks its ratio, so a corner drag that grows
    /// one axis while shrinking the other used to flip which axis drove the uniform scale — and
    /// the two candidate scales sit either side of 1 at the crossover, so the size stepped by the
    /// whole gap between them in a single frame.
    @Test func aspectLockedCornerNeverSteps() {
        // One model unit of translation can't scale the shape by more than a couple of units.
        let swept = stride(from: -400.0, through: 400.0, by: 1.0).map { CGSize(width: $0, height: -250) }
        #expect(largestWidthStep(device(), swept).step < 3)
    }

    /// The same continuity across the min-size floor, where the locked path used to clamp each
    /// axis before choosing the scale.
    @Test func aspectLockedCornerNeverStepsThroughTheFloor() {
        let swept = stride(from: 0.0, through: -900.0, by: -1.0).map { CGSize(width: $0, height: $0) }
        let result = largestWidthStep(device(), swept)
        #expect(result.step < 3)
        // The floor is a uniform scale, so it is the *short* side that lands on it.
        #expect(result.last == device().minResizeSize)
    }

    @Test func aspectLockedResizeKeepsTheRatio() {
        let shape = device()
        let state = ResizeGeometry.resize(
            shape: shape,
            edge: .bottomRight,
            translation: CGSize(width: 90, height: 40),
            lockAspectRatio: true
        )
        #expect(abs(state.newW / state.newH - shape.width / shape.height) < 0.0001)
    }

    /// Neither dimension may fall below the floor, and the ratio has to survive it — that is what
    /// `aspectLockedSize`'s uniform `minScale` buys over a per-axis clamp.
    @Test func aspectLockedResizeFloorsUniformly() {
        let shape = device()
        let state = ResizeGeometry.resize(
            shape: shape,
            edge: .bottomRight,
            translation: CGSize(width: -10_000, height: -10_000),
            lockAspectRatio: true
        )
        #expect(state.newW >= shape.minResizeSize)
        #expect(state.newH >= shape.minResizeSize)
        #expect(abs(state.newW / state.newH - shape.width / shape.height) < 0.0001)
    }

    /// Every handle pins the opposite corner or edge midpoint, rotated or not.
    @Test(arguments: ResizeEdge.allCases, [0.0, 30.0, 200.0])
    func anchorStaysPut(edge: ResizeEdge, rotation: Double) {
        let shape = device(rotation: rotation)
        let radians = rotation * .pi / 180

        func anchorInCanvas(_ frame: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat), _ edge: ResizeEdge) -> CGPoint {
            let anchor = edge.anchorPoint(width: frame.w, height: frame.h)
            let localX = anchor.x - frame.w / 2
            let localY = anchor.y - frame.h / 2
            return CGPoint(
                x: frame.x + frame.w / 2 + localX * cos(radians) - localY * sin(radians),
                y: frame.y + frame.h / 2 + localX * sin(radians) + localY * cos(radians)
            )
        }

        for locked in [true, false] {
            let state = ResizeGeometry.resize(
                shape: shape,
                edge: edge,
                translation: CGSize(width: 55, height: -35),
                lockAspectRatio: locked
            )
            let before = anchorInCanvas((shape.x, shape.y, shape.width, shape.height), edge)
            let after = anchorInCanvas((state.newX, state.newY, state.newW, state.newH), edge)
            #expect(abs(before.x - after.x) < 0.0001, "locked=\(locked)")
            #expect(abs(before.y - after.y) < 0.0001, "locked=\(locked)")
        }
    }

    /// An unlocked resize is still per-axis and still tracks the pointer one-for-one.
    @Test func unlockedResizeFollowsEachAxisIndependently() {
        let shape = rectangle()
        let state = ResizeGeometry.resize(
            shape: shape,
            edge: .bottomRight,
            translation: CGSize(width: 40, height: -60),
            lockAspectRatio: false
        )
        #expect(state.newW == shape.width + 40)
        #expect(state.newH == shape.height - 60)
        #expect(state.newX == shape.x)
        #expect(state.newY == shape.y)
    }

    @Test func unlockedResizeFloorsEachAxis() {
        let shape = rectangle()
        let state = ResizeGeometry.resize(
            shape: shape,
            edge: .topLeft,
            translation: CGSize(width: 10_000, height: 10_000),
            lockAspectRatio: false
        )
        #expect(state.newW == shape.minResizeSize)
        #expect(state.newH == shape.minResizeSize)
    }

    /// The pointer delta is taken in the shape's own frame: on a 90°-rotated shape a downward
    /// drag of the right-edge handle is what widens it.
    @Test func translationIsReadInTheShapesLocalFrame() {
        let shape = device(rotation: 90)
        let state = ResizeGeometry.resize(
            shape: shape,
            edge: .right,
            translation: CGSize(width: 0, height: 50),
            lockAspectRatio: false
        )
        #expect(abs(state.newW - (shape.width + 50)) < 0.0001)
        #expect(state.newH == shape.height)
    }

    /// A zero-translation tick — what `minimumDistance: 0` now delivers on a bare click — must
    /// leave the frame exactly alone, so it commits as a no-op and registers no undo step.
    @Test(arguments: [true, false], [0.0, 30.0, 200.0])
    func zeroTranslationIsIdentity(locked: Bool, rotation: Double) {
        let shape = device(rotation: rotation)
        let state = ResizeGeometry.resize(shape: shape, edge: .bottomRight, translation: .zero, lockAspectRatio: locked)
        #expect(abs(state.newW - shape.width) < 0.0001)
        #expect(abs(state.newH - shape.height) < 0.0001)
        #expect(abs(state.newX - shape.x) < 0.0001)
        #expect(abs(state.newY - shape.y) < 0.0001)
        #expect(!state.movedFrom(shape))
    }
}
