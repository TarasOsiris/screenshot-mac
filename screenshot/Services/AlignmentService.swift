import Foundation

enum AlignmentService {
    static func computeSnap(
        draggedShape: CanvasShapeModel,
        dragOffset: CGSize,
        otherShapes: [CanvasShapeModel],
        templateWidth: CGFloat,
        templateHeight: CGFloat,
        templateCount: Int,
        snapThreshold: CGFloat = 4
    ) -> SnapResult {
        // Use AABB for dragged shape at proposed position
        var proposed = draggedShape
        proposed.x += dragOffset.width
        proposed.y += dragOffset.height
        let dragBB = aabb(for: proposed)

        let dragLeft = dragBB.minX
        let dragRight = dragBB.maxX
        let dragCenterX = (dragBB.minX + dragBB.maxX) / 2
        let dragTop = dragBB.minY
        let dragBottom = dragBB.maxY
        let dragCenterY = (dragBB.minY + dragBB.maxY) / 2

        let dragVerticals = [dragLeft, dragCenterX, dragRight]
        let dragHorizontals = [dragTop, dragCenterY, dragBottom]

        // Collect target lines from other shapes
        var targetVerticals: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat)] = []
        var targetHorizontals: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat)] = []

        for shape in otherShapes {
            let bb = aabb(for: shape)
            let cx = (bb.minX + bb.maxX) / 2
            let cy = (bb.minY + bb.maxY) / 2
            targetVerticals.append((bb.minX, bb.minY, bb.maxY))
            targetVerticals.append((cx, bb.minY, bb.maxY))
            targetVerticals.append((bb.maxX, bb.minY, bb.maxY))
            targetHorizontals.append((bb.minY, bb.minX, bb.maxX))
            targetHorizontals.append((cy, bb.minX, bb.maxX))
            targetHorizontals.append((bb.maxY, bb.minX, bb.maxX))
        }

        // Template boundary lines
        for i in 0..<templateCount {
            let left = CGFloat(i) * templateWidth
            let right = left + templateWidth
            let center = left + templateWidth / 2
            targetVerticals.append((left, 0, templateHeight))
            targetVerticals.append((center, 0, templateHeight))
            targetVerticals.append((right, 0, templateHeight))
        }
        let totalWidth = templateWidth * CGFloat(templateCount)
        targetHorizontals.append((0, 0, totalWidth))
        targetHorizontals.append((templateHeight / 2, 0, totalWidth))
        targetHorizontals.append((templateHeight, 0, totalWidth))

        var snapDX: CGFloat = 0
        var snapDY: CGFloat = 0
        var guides: [AlignmentGuide] = []

        // Snap on X axis (vertical guides)
        if let match = findBestSnap(dragLines: dragVerticals, targets: targetVerticals, threshold: snapThreshold) {
            snapDX = match.delta
            guides.append(AlignmentGuide(
                axis: .vertical,
                position: match.targetPosition,
                start: min(match.targetRangeMin, dragTop),
                end: max(match.targetRangeMax, dragBottom)
            ))
        }

        // Snap on Y axis (horizontal guides)
        if let match = findBestSnap(dragLines: dragHorizontals, targets: targetHorizontals, threshold: snapThreshold) {
            snapDY = match.delta
            guides.append(AlignmentGuide(
                axis: .horizontal,
                position: match.targetPosition,
                start: min(match.targetRangeMin, dragLeft),
                end: max(match.targetRangeMax, dragRight)
            ))
        }

        let snappedOffset = CGSize(
            width: dragOffset.width + snapDX,
            height: dragOffset.height + snapDY
        )

        return SnapResult(snappedOffset: snappedOffset, guides: guides)
    }

    private static func findBestSnap(
        dragLines: [CGFloat],
        targets: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat)],
        threshold: CGFloat
    ) -> (delta: CGFloat, targetPosition: CGFloat, targetRangeMin: CGFloat, targetRangeMax: CGFloat)? {
        var bestDist = threshold + 1.0
        var bestMatch: (dragLine: CGFloat, target: (position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat))?

        for dLine in dragLines {
            for target in targets {
                let dist = abs(dLine - target.position)
                if dist < bestDist {
                    bestDist = dist
                    bestMatch = (dLine, target)
                }
            }
        }

        guard let match = bestMatch, bestDist <= threshold else { return nil }
        return (match.target.position - match.dragLine, match.target.position, match.target.rangeMin, match.target.rangeMax)
    }

    /// Compute axis-aligned bounding box for a shape (accounts for rotation).
    private static func aabb(for shape: CanvasShapeModel) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let cx = shape.x + shape.width / 2
        let cy = shape.y + shape.height / 2
        let hw = shape.width / 2
        let hh = shape.height / 2

        guard shape.rotation != 0 else {
            return (shape.x, shape.y, shape.x + shape.width, shape.y + shape.height)
        }

        let rad = shape.rotation * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        let newHW = hw * cosA + hh * sinA
        let newHH = hw * sinA + hh * cosA
        return (cx - newHW, cy - newHH, cx + newHW, cy + newHH)
    }
}
