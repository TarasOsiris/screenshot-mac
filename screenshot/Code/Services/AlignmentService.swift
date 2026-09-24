import CoreGraphics
import Foundation

nonisolated enum AlignmentService {
    nonisolated struct OtherShapeBounds {
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

        let targets = snapTargets(
            nearCenterX: dragCenterX,
            otherShapeBounds: otherShapeBounds,
            templateWidth: templateWidth,
            templateHeight: templateHeight,
            templateCount: templateCount
        )
        let x = snapAxis(.vertical, lines: dragVerticals, targets: targets.verticals, span: (dragTop, dragBottom), threshold: snapThreshold)
        let y = snapAxis(.horizontal, lines: dragHorizontals, targets: targets.horizontals, span: (dragLeft, dragRight), threshold: snapThreshold)

        let snappedOffset = CGSize(
            width: dragOffset.width + (x?.delta ?? 0),
            height: dragOffset.height + (y?.delta ?? 0)
        )
        let guides = [x?.guide, y?.guide].compactMap { $0 }

        return SnapResult(snappedOffset: snappedOffset, guides: guides)
    }

    enum ResizeSide {
        case min, max

        var sign: CGFloat { self == .min ? -1 : 1 }

        /// A vertical guide lines up an x edge; a horizontal one a y edge.
        func edge(of rect: CGRect, along axis: AlignmentAxis) -> CGFloat {
            switch (self, axis) {
            case (.min, .vertical): rect.minX
            case (.max, .vertical): rect.maxX
            case (.min, .horizontal): rect.minY
            case (.max, .horizontal): rect.maxY
            }
        }
    }

    /// Snaps only the edges a resize handle moves; the pinned edge and the center never do.
    static func computeResizeSnap(
        frame: CGRect,
        movingX: ResizeSide?,
        movingY: ResizeSide?,
        otherShapeBounds: [OtherShapeBounds],
        templateWidth: CGFloat,
        templateHeight: CGFloat,
        templateCount: Int,
        snapThreshold: CGFloat = 4
    ) -> ResizeSnapResult {
        let targets = snapTargets(
            nearCenterX: frame.midX,
            otherShapeBounds: otherShapeBounds,
            templateWidth: templateWidth,
            templateHeight: templateHeight,
            templateCount: templateCount
        )
        let x = movingX.flatMap {
            snapAxis(.vertical, lines: [$0.edge(of: frame, along: .vertical)], targets: targets.verticals,
                     span: (frame.minY, frame.maxY), threshold: snapThreshold)
        }
        let y = movingY.flatMap {
            snapAxis(.horizontal, lines: [$0.edge(of: frame, along: .horizontal)], targets: targets.horizontals,
                     span: (frame.minX, frame.maxX), threshold: snapThreshold)
        }
        return ResizeSnapResult(
            delta: CGSize(width: x?.delta ?? 0, height: y?.delta ?? 0),
            guides: [x?.guide, y?.guide].compactMap { $0 }
        )
    }

    /// `span` is the dragged shape's extent across the guide, so the line reaches both it and the target.
    private static func snapAxis(
        _ axis: AlignmentAxis,
        lines: [CGFloat],
        targets: [SnapTarget],
        span: (start: CGFloat, end: CGFloat),
        threshold: CGFloat
    ) -> (delta: CGFloat, guide: AlignmentGuide)? {
        guard let match = findBestSnap(dragLines: lines, targets: targets, threshold: threshold) else { return nil }
        return (match.delta, AlignmentGuide(
            axis: axis,
            position: match.targetPosition,
            start: min(match.targetRangeMin, span.start),
            end: max(match.targetRangeMax, span.end)
        ))
    }

    private typealias SnapTarget = (position: CGFloat, rangeMin: CGFloat, rangeMax: CGFloat, isCenter: Bool)

    /// Shape bounds and template edges/centers, limited to the templates beside the one under `nearCenterX`.
    private static func snapTargets(
        nearCenterX centerX: CGFloat,
        otherShapeBounds: [OtherShapeBounds],
        templateWidth: CGFloat,
        templateHeight: CGFloat,
        templateCount: Int
    ) -> (verticals: [SnapTarget], horizontals: [SnapTarget]) {
        let centerTemplateIndex = max(0, min(templateCount - 1, Int(centerX / templateWidth)))
        let minTemplateIndex = max(0, centerTemplateIndex - 1)
        let maxTemplateIndex = min(templateCount - 1, centerTemplateIndex + 1)
        let neighborLeft = CGFloat(minTemplateIndex) * templateWidth
        let neighborRight = CGFloat(maxTemplateIndex + 1) * templateWidth

        var verticals: [SnapTarget] = []
        var horizontals: [SnapTarget] = []
        verticals.reserveCapacity(otherShapeBounds.count * 3 + (maxTemplateIndex - minTemplateIndex + 1) * 3)
        horizontals.reserveCapacity(otherShapeBounds.count * 3 + 3)

        for bounds in otherShapeBounds {
            guard bounds.maxX > neighborLeft && bounds.minX < neighborRight else { continue }
            verticals.append((bounds.minX, bounds.minY, bounds.maxY, false))
            verticals.append((bounds.centerX, bounds.minY, bounds.maxY, true))
            verticals.append((bounds.maxX, bounds.minY, bounds.maxY, false))
            horizontals.append((bounds.minY, bounds.minX, bounds.maxX, false))
            horizontals.append((bounds.centerY, bounds.minX, bounds.maxX, true))
            horizontals.append((bounds.maxY, bounds.minX, bounds.maxX, false))
        }

        for i in minTemplateIndex...maxTemplateIndex {
            let left = CGFloat(i) * templateWidth
            let right = left + templateWidth
            let center = left + templateWidth / 2
            verticals.append((left, 0, templateHeight, false))
            verticals.append((center, 0, templateHeight, true))
            verticals.append((right, 0, templateHeight, false))
        }
        horizontals.append((0, neighborLeft, neighborRight, false))
        horizontals.append((templateHeight / 2, neighborLeft, neighborRight, true))
        horizontals.append((templateHeight, neighborLeft, neighborRight, false))

        return (verticals, horizontals)
    }

    private static func findBestSnap(
        dragLines: [CGFloat],
        targets: [SnapTarget],
        threshold: CGFloat
    ) -> (delta: CGFloat, targetPosition: CGFloat, targetRangeMin: CGFloat, targetRangeMax: CGFloat)? {
        var bestDist = threshold + 1.0
        var bestIsCenter = false
        var bestMatch: (dragLine: CGFloat, target: SnapTarget)?

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
