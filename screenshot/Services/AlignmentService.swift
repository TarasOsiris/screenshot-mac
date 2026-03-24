import Foundation

enum AlignmentService {
    struct OtherShapeBounds {
        let minX: CGFloat
        let minY: CGFloat
        let maxX: CGFloat
        let maxY: CGFloat
        let centerX: CGFloat
        let centerY: CGFloat

        init(shape: CanvasShapeModel) {
            let bb = shape.aabb
            minX = bb.minX
            minY = bb.minY
            maxX = bb.maxX
            maxY = bb.maxY
            centerX = (bb.minX + bb.maxX) / 2
            centerY = (bb.minY + bb.maxY) / 2
        }
    }

    static func makeSnapTargets(from shapes: [CanvasShapeModel]) -> [OtherShapeBounds] {
        shapes.map { OtherShapeBounds(shape: $0) }
    }

    static func computeSnap(
        draggedShape: CanvasShapeModel,
        dragOffset: CGSize,
        otherShapes: [CanvasShapeModel],
        templateWidth: CGFloat,
        templateHeight: CGFloat,
        templateCount: Int,
        snapThreshold: CGFloat = 4
    ) -> SnapResult {
        computeSnap(
            draggedShape: draggedShape,
            dragOffset: dragOffset,
            otherShapeBounds: makeSnapTargets(from: otherShapes),
            templateWidth: templateWidth,
            templateHeight: templateHeight,
            templateCount: templateCount,
            snapThreshold: snapThreshold
        )
    }

    static func computeSnap(
        draggedShape: CanvasShapeModel,
        dragOffset: CGSize,
        otherShapeBounds: [OtherShapeBounds],
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
        targetVerticals.reserveCapacity(otherShapeBounds.count * 3 + (maxTemplateIndex - minTemplateIndex + 1) * 3)
        targetHorizontals.reserveCapacity(otherShapeBounds.count * 3 + 3)

        for bounds in otherShapeBounds {
            // Skip shapes that don't overlap the neighbor template range
            guard bounds.maxX > neighborLeft && bounds.minX < neighborRight else { continue }
            targetVerticals.append((bounds.minX, bounds.minY, bounds.maxY, false))
            targetVerticals.append((bounds.centerX, bounds.minY, bounds.maxY, true))
            targetVerticals.append((bounds.maxX, bounds.minY, bounds.maxY, false))
            targetHorizontals.append((bounds.minY, bounds.minX, bounds.maxX, false))
            targetHorizontals.append((bounds.centerY, bounds.minX, bounds.maxX, true))
            targetHorizontals.append((bounds.maxY, bounds.minX, bounds.maxX, false))
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
        guides.reserveCapacity(2)

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
