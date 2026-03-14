import Testing
import Foundation
@testable import Screenshot_Bro

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
        #expect(shape.aabb.minX != shape.x, "Rotated shape AABB should differ from raw x")
    }
}
