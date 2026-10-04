import SceneKit
@testable import Screenshot_Bro
import Testing

struct SCNNodeBoundsTests {

    private func expectVector(_ actual: SCNVector3, _ x: Double, _ y: Double, _ z: Double) {
        let tolerance = 1e-4
        #expect(abs(Double(actual.x) - x) < tolerance, "x was \(actual.x), expected \(x)")
        #expect(abs(Double(actual.y) - y) < tolerance, "y was \(actual.y), expected \(y)")
        #expect(abs(Double(actual.z) - z) < tolerance, "z was \(actual.z), expected \(z)")
    }

    private func boxNode(width: CGFloat, height: CGFloat, length: CGFloat) -> SCNNode {
        SCNNode(geometry: SCNBox(width: width, height: height, length: length, chamferRadius: 0))
    }

    @Test func worldBoundsFollowsParentTranslationAndScale() {
        let root = SCNNode()
        let parent = SCNNode()
        parent.position = SCNVector3(10, 0, 0)
        parent.scale = SCNVector3(2, 2, 2)
        let box = boxNode(width: 2, height: 4, length: 6)
        box.position = SCNVector3(0, 1, 0)
        parent.addChildNode(box)
        root.addChildNode(parent)

        let bounds = root.worldBounds()
        expectVector(bounds.min, 8, -2, -6)
        expectVector(bounds.max, 12, 6, 6)
    }

    @Test func worldBoundsAccountsForRotation() {
        let box = boxNode(width: 2, height: 4, length: 1)
        box.eulerAngles.z = .pi / 2

        let bounds = box.worldBounds()
        expectVector(bounds.min, -2, -1, -0.5)
        expectVector(bounds.max, 2, 1, 0.5)
    }

    @Test func worldBoundsSkipsEmptyLeaves() {
        let root = SCNNode()
        root.addChildNode(boxNode(width: 2, height: 2, length: 2))
        let light = SCNNode()
        light.position = SCNVector3(100, 100, 100)
        root.addChildNode(light)

        let bounds = root.worldBounds()
        expectVector(bounds.min, -1, -1, -1)
        expectVector(bounds.max, 1, 1, 1)
    }

    @Test func worldBoundsOfEmptyNodeIsZero() {
        let bounds = SCNNode().worldBounds()
        expectVector(bounds.min, 0, 0, 0)
        expectVector(bounds.max, 0, 0, 0)
    }

    @Test func boundsCoveringPoints() {
        let bounds = SCNNode.bounds(covering: [
            SCNVector3(1, -2, 3),
            SCNVector3(-4, 5, 0),
            SCNVector3(2, 0, -6),
        ])
        expectVector(bounds.min, -4, -2, -6)
        expectVector(bounds.max, 2, 5, 3)
        let empty = SCNNode.bounds(covering: [])
        expectVector(empty.min, 0, 0, 0)
        expectVector(empty.max, 0, 0, 0)
    }

    @Test func firstNodeInSubtreeFindsMaterialDepthFirst() {
        let root = SCNNode()
        let plain = boxNode(width: 1, height: 1, length: 1)
        let nested = SCNNode()
        let screen = boxNode(width: 1, height: 1, length: 1)
        let material = SCNMaterial()
        material.name = "Display"
        screen.geometry?.materials = [material]
        nested.addChildNode(screen)
        root.addChildNode(plain)
        root.addChildNode(nested)

        #expect(root.firstNodeInSubtree(withMaterialNamed: "Display") === screen)
        #expect(root.firstNodeInSubtree(withMaterialNamed: "Missing") == nil)
    }
}
