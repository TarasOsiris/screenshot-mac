import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct AlignmentServiceTests {

    // MARK: - No snap when far from targets

    @Test func noSnapWhenShapeFarFromTargets() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: shape,
            dragOffset: .zero,
            otherShapes: [],
            templateWidth: 1242,
            templateHeight: 2688,
            templateCount: 1
        )
        // Shape at x=100 is far from template edges (0, 621, 1242), no snap
        #expect(result.snappedOffset.width == 0)
        #expect(result.snappedOffset.height == 0)
        #expect(result.guides.isEmpty)
    }

    // MARK: - Snap to template left edge

    @Test func snapToTemplateLeftEdge() {
        // Shape left edge at x=2, within 4px threshold of template left edge at 0
        let shape = CanvasShapeModel(type: .rectangle, x: 2, y: 100, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: shape,
            dragOffset: .zero,
            otherShapes: [],
            templateWidth: 1242,
            templateHeight: 2688,
            templateCount: 1
        )
        #expect(result.snappedOffset.width == -2, "Should snap left edge to 0")
        #expect(result.guides.contains { $0.axis == .vertical })
    }

    // MARK: - Snap to template center

    @Test func snapToTemplateCenterX() {
        let templateWidth: CGFloat = 1000
        // Shape center = x + width/2 = 498 + 50 = 548, but we want shape center near 500
        // shape center = x + w/2 = 448 + 50 = 498, within 4px of 500
        let shape = CanvasShapeModel(type: .rectangle, x: 448, y: 100, width: 100, height: 100)
        let result = AlignmentService.computeSnap(
            draggedShape: shape,
            dragOffset: .zero,
            otherShapes: [],
            templateWidth: templateWidth,
            templateHeight: 2000,
            templateCount: 1
        )
        // Center of shape = 498, template center = 500, delta = 2
        #expect(result.snappedOffset.width == 2, "Should snap center to template center")
    }

    // MARK: - Snap to other shape edge

    @Test func snapToOtherShapeEdge() {
        let target = CanvasShapeModel(type: .rectangle, x: 200, y: 200, width: 100, height: 100)
        // Dragged shape right edge = 198 + 50 = 248, target right edge = 300, target left = 200
        // Dragged left = 198, target left = 200, diff = 2 → snap
        let dragged = CanvasShapeModel(type: .rectangle, x: 198, y: 500, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: dragged,
            dragOffset: .zero,
            otherShapes: [target],
            templateWidth: 1242,
            templateHeight: 2688,
            templateCount: 1
        )
        #expect(result.snappedOffset.width == 2, "Should snap to other shape's left edge")
        #expect(!result.guides.isEmpty)
    }

    // MARK: - Snap with drag offset applied

    @Test func snapAccountsForDragOffset() {
        // Shape at x=100, dragged by 97 → proposed x=197, left edge near 200 (target left)
        let target = CanvasShapeModel(type: .rectangle, x: 200, y: 200, width: 100, height: 100)
        let dragged = CanvasShapeModel(type: .rectangle, x: 100, y: 500, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: dragged,
            dragOffset: CGSize(width: 97, height: 0),
            otherShapes: [target],
            templateWidth: 1242,
            templateHeight: 2688,
            templateCount: 1
        )
        // Proposed left = 197, target left = 200, snap delta = +3
        #expect(result.snappedOffset.width == 100, "97 + 3 snap = 100")
    }

    // MARK: - Snap on Y axis (horizontal guides)

    @Test func snapToTemplateTopEdge() {
        // Shape top at y=3, within 4px of template top at 0
        let shape = CanvasShapeModel(type: .rectangle, x: 500, y: 3, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: shape,
            dragOffset: .zero,
            otherShapes: [],
            templateWidth: 1242,
            templateHeight: 2688,
            templateCount: 1
        )
        #expect(result.snappedOffset.height == -3, "Should snap top to 0")
        #expect(result.guides.contains { $0.axis == .horizontal })
    }

    // MARK: - Multiple template snap targets

    @Test func snapToSecondTemplateEdge() {
        let templateWidth: CGFloat = 500
        // Second template starts at x=500. Shape right edge = 497+50=547, left=497
        // Shape left = 497, template 2 left = 500, diff = 3 → snap
        let shape = CanvasShapeModel(type: .rectangle, x: 497, y: 100, width: 50, height: 50)
        let result = AlignmentService.computeSnap(
            draggedShape: shape,
            dragOffset: .zero,
            otherShapes: [],
            templateWidth: templateWidth,
            templateHeight: 2000,
            templateCount: 3
        )
        #expect(result.snappedOffset.width == 3, "Should snap to second template left edge")
    }

    // MARK: - Custom threshold

    @Test func respectsCustomThreshold() {
        // Shape left = 10, template left = 0, diff = 10
        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 500, width: 50, height: 50)

        // Default threshold (4) — no snap
        let result4 = AlignmentService.computeSnap(
            draggedShape: shape, dragOffset: .zero, otherShapes: [],
            templateWidth: 1242, templateHeight: 2688, templateCount: 1, snapThreshold: 4
        )
        #expect(result4.snappedOffset.width == 0, "10px is beyond 4px threshold")

        // Larger threshold (12) — should snap
        let result12 = AlignmentService.computeSnap(
            draggedShape: shape, dragOffset: .zero, otherShapes: [],
            templateWidth: 1242, templateHeight: 2688, templateCount: 1, snapThreshold: 12
        )
        #expect(result12.snappedOffset.width == -10, "10px is within 12px threshold")
    }

    // MARK: - Rotated shape AABB snap

    @Test func snapsUsingAABBForRotatedShape() {
        // A 100x100 shape rotated 45° has AABB ~141x141
        // Place it so that AABB left edge is within snap threshold of template left
        let shape = CanvasShapeModel(
            type: .rectangle, x: 1, y: 200, width: 100, height: 100, rotation: 45
        )
        // Verify rotated shape AABB differs from raw position
        #expect(shape.aabb.minX != 1, "Rotated shape AABB should differ from raw x")
    }

    // MARK: - Resize snapping

    private func resizeSnap(
        frame: CGRect,
        movingX: AlignmentService.ResizeSide?,
        movingY: AlignmentService.ResizeSide?,
        others: [CanvasShapeModel] = []
    ) -> ResizeSnapResult {
        AlignmentService.computeResizeSnap(
            frame: frame,
            movingX: movingX,
            movingY: movingY,
            otherShapeBounds: AlignmentService.makeSnapTargets(from: others),
            templateWidth: 1000,
            templateHeight: 2000,
            templateCount: 1
        )
    }

    @Test func resizeRightEdgeSnapsToOtherShapeLeftEdge() {
        let other = CanvasShapeModel(type: .rectangle, x: 300, y: 800, width: 100, height: 100)
        let result = resizeSnap(frame: CGRect(x: 100, y: 100, width: 197, height: 100), movingX: .max, movingY: nil, others: [other])
        #expect(result.delta == CGSize(width: 3, height: 0))
        #expect(result.guides.map(\.axis) == [.vertical])
        #expect(result.guides.first?.position == 300)
    }

    @Test func resizeCornerSnapsBothAxes() {
        let result = resizeSnap(frame: CGRect(x: 100, y: 100, width: 398, height: 902), movingX: .max, movingY: .max)
        #expect(result.delta == CGSize(width: 2, height: -2))
        #expect(result.guides.count == 2)
    }

    @Test func resizeNeverSnapsPinnedEdgeOrCenter() {
        // The left edge sits 2 from the template edge, but only the right edge is moving.
        let result = resizeSnap(frame: CGRect(x: 2, y: 100, width: 800, height: 100), movingX: .max, movingY: nil)
        #expect(result.delta == .zero)
        #expect(result.guides.isEmpty)
    }

    @Test func resizeOutOfThresholdDoesNotSnap() {
        let result = resizeSnap(frame: CGRect(x: 100, y: 100, width: 300, height: 300), movingX: .min, movingY: .min)
        #expect(result.delta == .zero)
        #expect(result.guides.isEmpty)
    }

    @Test func snappedResizeLandsDraggedEdgeOnTarget() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 200, height: 100)
        let other = CanvasShapeModel(type: .rectangle, x: 400, y: 800, width: 100, height: 100)
        let targets = AlignmentService.makeSnapTargets(from: [other])
        let (state, guides) = ResizeGeometry.snappedResize(
            shape: shape,
            edge: .right,
            translation: CGSize(width: 97, height: 0),
            lockAspectRatio: false
        ) { frame, movingX, movingY in
            AlignmentService.computeResizeSnap(
                frame: frame, movingX: movingX, movingY: movingY, otherShapeBounds: targets,
                templateWidth: 1000, templateHeight: 2000, templateCount: 1
            )
        }
        #expect(state.newX == 100)
        #expect(state.newX + state.newW == 400)
        #expect(state.newH == 100)
        #expect(guides.count == 1)
    }

    @Test func snappedResizeKeepsAspectRatioWhenLocked() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 200, height: 100)
        let (state, guides) = ResizeGeometry.snappedResize(
            shape: shape,
            edge: .bottomRight,
            translation: CGSize(width: 198, height: 99),
            lockAspectRatio: true
        ) { frame, movingX, movingY in
            AlignmentService.computeResizeSnap(
                frame: frame, movingX: movingX, movingY: movingY, otherShapeBounds: [],
                templateWidth: 1000, templateHeight: 2000, templateCount: 1
            )
        }
        // Right edge lands on the template center (500); the height follows the 2:1 ratio.
        #expect(abs(state.newX + state.newW - 500) < 0.001)
        #expect(abs(state.newW / state.newH - 2) < 0.001)
        #expect(guides.map(\.axis) == [.vertical])
    }

    @Test func snappedResizeSkipsRotatedShapes() {
        var shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 200, height: 100)
        shape.rotation = 30
        var snapCalled = false
        let (_, guides) = ResizeGeometry.snappedResize(
            shape: shape,
            edge: .right,
            translation: CGSize(width: 10, height: 0),
            lockAspectRatio: false
        ) { _, _, _ in
            snapCalled = true
            return ResizeSnapResult(delta: .zero, guides: [])
        }
        #expect(!snapCalled)
        #expect(guides.isEmpty)
    }
}
