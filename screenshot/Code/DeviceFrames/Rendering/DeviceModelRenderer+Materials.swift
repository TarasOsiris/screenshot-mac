#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SceneKit

nonisolated extension DeviceModelRenderer {
    static func applyScreenTexture(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        screenContents: CGImage?,
        screenContentsIdentity: String?
    ) {
        let prepared = preparedScreenContents(from: screenContents, identity: screenContentsIdentity)
        switch modelSpec.screenRenderingMode {
        case .replaceMaterial:
            applyScreenReplacementMaterial(in: contentNode, modelSpec: modelSpec, screenContents: prepared)
        case .overlayPlane:
            applyScreenOverlayPlane(in: contentNode, modelSpec: modelSpec, screenContents: prepared)
        }
    }

    static func applyBodyMaterials(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        tintColor: NSColor? = nil,
        bodyMaterial: DeviceBodyMaterial
    ) {
        let isGlossy = bodyMaterial.resolvedFinish == .glossy
        let metalness = CGFloat(bodyMaterial.resolvedMetalness)
        let roughness = CGFloat(bodyMaterial.resolvedRoughness)

        contentNode.enumerateHierarchy { node, _ in
            guard let originalGeometry = node.geometry,
                  let clonedGeometry = originalGeometry.copy() as? SCNGeometry else { return }

            clonedGeometry.materials = originalGeometry.materials.map { material in
                guard shouldStyleBodyMaterial(material, screenMaterialName: modelSpec.screenMaterialName) else {
                    return material.copy() as? SCNMaterial ?? SCNMaterial()
                }

                let styled = material.copy() as? SCNMaterial ?? SCNMaterial()
                styled.name = material.name
                if let tintColor {
                    styled.multiply.contents = tintColor
                }
                styled.fresnelExponent = 0.0
                styled.locksAmbientWithDiffuse = true

                if isGlossy {
                    styled.lightingModel = .physicallyBased
                    styled.metalness.contents = metalness
                    styled.roughness.contents = roughness
                    styled.specular.contents = NSColor.white
                    styled.reflective.contents = NSColor(white: 0.15, alpha: 1.0)
                    styled.shininess = 1.0 - roughness
                } else {
                    styled.lightingModel = .lambert
                    styled.specular.contents = NSColor.black
                    styled.reflective.contents = NSColor.black
                    styled.metalness.contents = 0.0
                    styled.roughness.contents = 1.0
                    styled.shininess = 0.0
                }
                return styled
            }
            node.geometry = clonedGeometry
        }
    }

    static func removeDisabledModelNodes(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec
    ) {
        guard !modelSpec.disabledNodeNames.isEmpty else { return }

        var nodesToRemove: [SCNNode] = []
        contentNode.enumerateHierarchy { node, _ in
            if let name = node.name, modelSpec.disabledNodeNames.contains(name) {
                nodesToRemove.append(node)
            }
        }

        for node in nodesToRemove {
            node.removeFromParentNode()
        }
    }

    private static func shouldStyleBodyMaterial(
        _ material: SCNMaterial,
        screenMaterialName: String?
    ) -> Bool {
        guard material.name != screenMaterialName else { return false }
        let name = material.name?.lowercased() ?? ""
        if name.contains("glass") || name.contains("lens") {
            return false
        }
        return true
    }

    private static func applyScreenReplacementMaterial(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        screenContents: Any
    ) {
        guard let screenNode = findScreenNode(in: contentNode, modelSpec: modelSpec),
              let geometry = screenNode.geometry?.copy() as? SCNGeometry else {
            return
        }

        let remappedGeometry = remapUVsToFullRange(
            geometry,
            padding: modelSpec.screenUVPadding,
            offsetY: modelSpec.screenUVOffsetY
        )

        let materials = remappedGeometry.materials.map { material -> SCNMaterial in
            guard material.name == modelSpec.screenMaterialName else {
                return material.copy() as? SCNMaterial ?? SCNMaterial()
            }

            let replacement = material.copy() as? SCNMaterial ?? SCNMaterial()
            replacement.name = material.name
            configureScreenMaterial(
                replacement,
                contents: screenContents,
                contentsTransform: screenTexture90CWTransform
            )
            return replacement
        }
        remappedGeometry.materials = materials
        screenNode.geometry = remappedGeometry
    }

    private static func applyScreenOverlayPlane(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        screenContents: Any
    ) {
        guard let screenNode = findScreenNode(in: contentNode, modelSpec: modelSpec) else {
            return
        }

        let bounds = screenNode.worldBounds()
        let screenWidth = CGFloat(bounds.max.x - bounds.min.x)
        let screenHeight = CGFloat(bounds.max.y - bounds.min.y)
        guard screenWidth > 0.001, screenHeight > 0.001 else {
            return
        }

        let plane = SCNPlane(width: screenWidth, height: screenHeight)
        plane.cornerRadius = min(screenWidth / 2, screenHeight * 0.075)

        let material = SCNMaterial()
        material.name = "ScreenOverlay"
        configureScreenMaterial(material, contents: screenContents)
        plane.materials = [material]

        // The device's front face, not the screen mesh: a model's cover glass (the Pro Max's is
        // translucent black) can sit above its Display mesh and would tint the screenshot.
        let centerInWorld = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            contentNode.boundingBox.max.z + 0.001
        )
        let centerInContent = contentNode.convertPosition(centerInWorld, from: nil)

        let planeNode = SCNNode(geometry: plane)
        planeNode.name = "screenTextureOverlay"
        planeNode.position = centerInContent
        contentNode.addChildNode(planeNode)
    }

    /// Emission only: under `.constant` lighting diffuse adds to emission and doubles the screenshot.
    private static func configureScreenMaterial(
        _ material: SCNMaterial,
        contents: Any,
        contentsTransform: SCNMatrix4 = SCNMatrix4Identity
    ) {
        material.diffuse.contents = NSColor.black
        material.ambient.contents = NSColor.black
        material.emission.contents = contents
        material.emission.intensity = screenEmissionIntensity
        material.emission.contentsTransform = contentsTransform
        material.emission.wrapS = .clamp
        material.emission.wrapT = .clamp
        material.multiply.contents = NSColor.white
        material.transparent.contents = NSColor.white
        material.reflective.contents = NSColor.black
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
    }

    private static func remapUVsToFullRange(
        _ geometry: SCNGeometry,
        padding: CGFloat = 0,
        offsetY: CGFloat = 0
    ) -> SCNGeometry {
        guard let uvSource = geometry.sources.first(where: { $0.semantic == .texcoord }) else {
            return geometry
        }

        let vectorCount = uvSource.vectorCount
        let data = uvSource.data
        let stride = uvSource.dataStride
        let offset = uvSource.dataOffset

        var rawUVs = [CGPoint]()
        rawUVs.reserveCapacity(vectorCount)
        var minU: Float = .greatestFiniteMagnitude
        var maxU: Float = -.greatestFiniteMagnitude
        var minV: Float = .greatestFiniteMagnitude
        var maxV: Float = -.greatestFiniteMagnitude
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.baseAddress!
            for i in 0..<vectorCount {
                let base = bytes + stride * i + offset
                let u = base.load(as: Float.self)
                let v = (base + 4).load(as: Float.self)
                minU = min(minU, u)
                maxU = max(maxU, u)
                minV = min(minV, v)
                maxV = max(maxV, v)
                rawUVs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }

        let rangeU = maxU - minU
        let rangeV = maxV - minV
        guard rangeU > 0.001, rangeV > 0.001 else { return geometry }

        let totalU = 1.0 + 2.0 * padding
        let totalV = 1.0 + 2.0 * padding
        // `offsetY` lands on u because `screenTexture90CWTransform` maps mesh u onto the image's vertical axis.
        for index in 0..<rawUVs.count {
            rawUVs[index] = CGPoint(
                x: (rawUVs[index].x - CGFloat(minU)) / CGFloat(rangeU) * totalU - padding + offsetY,
                y: (rawUVs[index].y - CGFloat(minV)) / CGFloat(rangeV) * totalV - padding
            )
        }

        let newUVSource = SCNGeometrySource(textureCoordinates: rawUVs)
        let otherSources = geometry.sources.filter { $0.semantic != .texcoord }
        let newGeometry = SCNGeometry(sources: otherSources + [newUVSource], elements: geometry.elements)
        newGeometry.materials = geometry.materials
        return newGeometry
    }

    private static let screenTexture90CWTransform: SCNMatrix4 = {
        let toOrigin = SCNMatrix4MakeTranslation(-0.5, -0.5, 0)
        let rotate = SCNMatrix4MakeRotation(-.pi / 2, 0, 0, 1)
        let flipH = SCNMatrix4MakeScale(-1, 1, 1)
        let toCenter = SCNMatrix4MakeTranslation(0.5, 0.5, 0)
        return SCNMatrix4Mult(SCNMatrix4Mult(SCNMatrix4Mult(toOrigin, rotate), flipH), toCenter)
    }()

    private static func findScreenNode(in root: SCNNode, modelSpec: DeviceFrameModelSpec) -> SCNNode? {
        if let screenMaterialName = modelSpec.screenMaterialName,
           let node = root.firstNodeInSubtree(withMaterialNamed: screenMaterialName) {
            return node
        }

        let frontZ = root.boundingBox.max.z
        var candidate: (node: SCNNode, area: SCNFloat)?
        root.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            let bounds = geometry.boundingBox
            let dx = bounds.max.x - bounds.min.x
            let dy = bounds.max.y - bounds.min.y
            let dz = bounds.max.z - bounds.min.z
            guard dx > 0, dy > 0, dz < 1 else { return }
            let nodeBounds = node.worldBounds()
            let distanceFromFront = abs(nodeBounds.max.z - frontZ)
            guard distanceFromFront < 2 else { return }
            let area = dx * dy
            if candidate == nil || area > candidate?.area ?? 0 {
                candidate = (node, area)
            }
        }
        return candidate?.node
    }
}
