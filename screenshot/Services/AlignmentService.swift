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
        let dragBB = proposed.aabb

        let dragLeft = dragBB.minX
        let dragRight = dragBB.maxX
        let dragCenterX = (dragBB.minX + dragBB.maxX) / 2
        let dragTop = dragBB.minY
        let dragBottom = dragBB.maxY
        let dragCenterY = (dragBB.minY + dragBB.maxY) / 2

        let dragVerticals = [dragLeft, dragCenterX, dragRight]
        let dragHorizontals = [dragTop, dragCenterY, dragBottom]

        // Only snap to nearest neighbor templates
        let dragTemplateCenterIndex = max(0, min(templateCount - 1, Int(dragCenterX / templateWidth)))
        let minTemplateIndex = max(0, dragTemplateCenterIndex - 1)
        let maxTemplateIndex = min(templateCount - 1, dragTemplateCenterIndex + 1)
        let neighborLeft = CGFloat(minTemplateIndex) * templateWidth
        let neighborRight = CGFloat(maxTemplateIndex + 1) * templateWidth

        // Collect target lines from shapes in nearby templates only
        var targetVerticals: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat, isCenter: Bool)] = []
        var targetHorizontals: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat, isCenter: Bool)] = []

        for shape in otherShapes {
            let bb = shape.aabb
            // Skip shapes that don't overlap the neighbor template range
            guard bb.maxX > neighborLeft && bb.minX < neighborRight else { continue }
            let cx = (bb.minX + bb.maxX) / 2
            let cy = (bb.minY + bb.maxY) / 2
            targetVerticals.append((bb.minX, bb.minY, bb.maxY, false))
            targetVerticals.append((cx, bb.minY, bb.maxY, true))
            targetVerticals.append((bb.maxX, bb.minY, bb.maxY, false))
            targetHorizontals.append((bb.minY, bb.minX, bb.maxX, false))
            targetHorizontals.append((cy, bb.minX, bb.maxX, true))
            targetHorizontals.append((bb.maxY, bb.minX, bb.maxX, false))
        }

        // Template boundary lines for nearby templates
        for i in minTemplateIndex...maxTemplateIndex {
            let left = CGFloat(i) * templateWidth
            let right = left + templateWidth
            let center = left + templateWidth / 2
            targetVerticals.append((left, 0, templateHeight, false))
            targetVerticals.append((center, 0, templateHeight, true))
            targetVerticals.append((right, 0, templateHeight, false))
        }
        targetHorizontals.append((0, neighborLeft, neighborRight, false))
        targetHorizontals.append((templateHeight / 2, neighborLeft, neighborRight, true))
        targetHorizontals.append((templateHeight, neighborLeft, neighborRight, false))

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
        targets: [(position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat, isCenter: Bool)],
        threshold: CGFloat
    ) -> (delta: CGFloat, targetPosition: CGFloat, targetRangeMin: CGFloat, targetRangeMax: CGFloat)? {
        var bestDist = threshold + 1.0
        var bestIsCenter = false
        var bestMatch: (dragLine: CGFloat, target: (position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat, isCenter: Bool))?

        for dLine in dragLines {
            for target in targets {
                let dist = abs(dLine - target.position)
                guard dist <= threshold else { continue }
                // Center targets take priority over edges within threshold
                let isBetter = bestMatch == nil ||
                    (target.isCenter && !bestIsCenter) ||
                    (target.isCenter == bestIsCenter && dist < bestDist)
                if isBetter {
                    bestDist = dist
                    bestIsCenter = target.isCenter
                    bestMatch = (dLine, target)
                }
            }
        }

        guard let match = bestMatch else { return nil }
        return (match.target.position - match.dragLine, match.target.position, match.target.rangeMin, match.target.rangeMax)
    }

}
