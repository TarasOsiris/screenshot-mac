import SceneKit

nonisolated extension SCNNode {
    func firstNodeInSubtree(withMaterialNamed materialName: String) -> SCNNode? {
        var match: SCNNode?
        enumerateHierarchy { node, stop in
            guard node.geometry?.materials.contains(where: { $0.name == materialName }) == true else { return }
            match = node
            stop.pointee = true
        }
        return match
    }

    /// Scene-space box around every geometry in the subtree; empty leaves (lights, cameras) don't count.
    func worldBounds() -> (min: SCNVector3, max: SCNVector3) {
        var accumulated: (min: SCNVector3, max: SCNVector3)?

        if let geometry {
            let (localMin, localMax) = geometry.boundingBox
            let corners = [
                SCNVector3(localMin.x, localMin.y, localMin.z),
                SCNVector3(localMin.x, localMin.y, localMax.z),
                SCNVector3(localMin.x, localMax.y, localMin.z),
                SCNVector3(localMin.x, localMax.y, localMax.z),
                SCNVector3(localMax.x, localMin.y, localMin.z),
                SCNVector3(localMax.x, localMin.y, localMax.z),
                SCNVector3(localMax.x, localMax.y, localMin.z),
                SCNVector3(localMax.x, localMax.y, localMax.z),
            ].map { convertPosition($0, to: nil) }

            accumulated = Self.bounds(covering: corners)
        }

        for child in childNodes {
            let childBounds = child.worldBounds()
            let isEmptyLeaf =
                child.geometry == nil &&
                child.childNodes.isEmpty &&
                childBounds.min.x == childBounds.max.x &&
                childBounds.min.y == childBounds.max.y &&
                childBounds.min.z == childBounds.max.z
            if isEmptyLeaf {
                continue
            }
            if let existing = accumulated {
                accumulated = (
                    min: SCNVector3(
                        min(existing.min.x, childBounds.min.x),
                        min(existing.min.y, childBounds.min.y),
                        min(existing.min.z, childBounds.min.z)
                    ),
                    max: SCNVector3(
                        max(existing.max.x, childBounds.max.x),
                        max(existing.max.y, childBounds.max.y),
                        max(existing.max.z, childBounds.max.z)
                    )
                )
            } else {
                accumulated = childBounds
            }
        }

        return accumulated ?? (SCNVector3Zero, SCNVector3Zero)
    }

    static func bounds(covering points: [SCNVector3]) -> (min: SCNVector3, max: SCNVector3) {
        guard let first = points.first else { return (SCNVector3Zero, SCNVector3Zero) }
        var minV = first
        var maxV = first
        for point in points.dropFirst() {
            minV.x = min(minV.x, point.x)
            minV.y = min(minV.y, point.y)
            minV.z = min(minV.z, point.z)
            maxV.x = max(maxV.x, point.x)
            maxV.y = max(maxV.y, point.y)
            maxV.z = max(maxV.z, point.z)
        }
        return (minV, maxV)
    }
}
