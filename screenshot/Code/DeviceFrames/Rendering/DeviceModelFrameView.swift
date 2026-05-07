import AppKit
import SceneKit
import SwiftUI

struct DeviceModelFrameView: View {
    private static let modelSnapshotScale: CGFloat = 3
    private static let snapshotExposureOffset: CGFloat = -0.7
    private static let modelSceneCache: NSCache<NSString, SCNScene> = {
        let cache = NSCache<NSString, SCNScene>()
        cache.countLimit = 4
        return cache
    }()

    let frame: DeviceFrame
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?
    let pitch: Double
    let yaw: Double
    let bodyMaterial: DeviceBodyMaterial
    let lighting: DeviceLighting
    let modelRenderingMode: DeviceModelRenderingMode
    let invisibleCornerRadius: CGFloat
    let invisibleOutlineWidth: CGFloat
    let invisibleOutlineColor: Color

    var body: some View {
        switch modelRenderingMode {
        case .live:
            LiveDeviceModelView(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                pitch: pitch,
                yaw: yaw,
                bodyMaterial: bodyMaterial,
                lighting: lighting,
                bodyTintColor: NSColor(bodyColor)
            )
            .frame(width: width, height: height)
        case .snapshot:
            if let image = Self.snapshotDeviceModel(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                pitch: pitch,
                yaw: yaw,
                bodyMaterial: bodyMaterial,
                lighting: lighting,
                bodyTintColor: NSColor(bodyColor)
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            } else {
                fallbackView
            }
        }
    }

    private var fallbackView: some View {
        ProgrammaticDeviceFrameView(
            category: frame.fallbackCategory,
            bodyColor: bodyColor,
            width: width,
            height: height,
            screenshotImage: screenshotImage,
            invisibleCornerRadius: invisibleCornerRadius,
            invisibleOutlineWidth: invisibleOutlineWidth,
            invisibleOutlineColor: invisibleOutlineColor
        )
    }

    fileprivate static func snapshotDeviceModel(
        frame: DeviceFrame,
        width: CGFloat,
        height: CGFloat,
        screenshotImage: NSImage?,
        pitch: Double,
        yaw: Double,
        bodyMaterial: DeviceBodyMaterial,
        lighting: DeviceLighting,
        bodyTintColor: NSColor? = nil
    ) -> NSImage? {
        let safeWidth = max(1, (width * modelSnapshotScale).rounded(.up))
        let safeHeight = max(1, (height * modelSnapshotScale).rounded(.up))
        let viewportSize = CGSize(width: safeWidth, height: safeHeight)
        guard let (scene, cameraNode) = makeDeviceModelScene(
            frame: frame,
            viewportSize: viewportSize,
            screenshotImage: screenshotImage,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTintColor: bodyTintColor
        ) else {
            return nil
        }

        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        if let camera = cameraNode.camera {
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = snapshotExposureOffset
        }
        let image = renderer.snapshot(
            atTime: 0,
            with: CGSize(width: safeWidth, height: safeHeight),
            antialiasingMode: .multisampling4X
        )
        image.size = NSSize(width: max(1, width), height: max(1, height))
        return image
    }

    static func makeDeviceModelScene(
        frame: DeviceFrame,
        viewportSize: CGSize,
        screenshotImage: NSImage?,
        pitch: Double,
        yaw: Double,
        bodyMaterial: DeviceBodyMaterial,
        lighting: DeviceLighting,
        bodyTintColor: NSColor? = nil
    ) -> (SCNScene, SCNNode)? {
        guard let modelSpec = frame.modelSpec,
              let scene = clonedBaseScene(for: modelSpec) else {
            return nil
        }

        let sceneRoot = scene.rootNode
        let contentNode = SCNNode()
        contentNode.name = "deviceModelContent"
        for child in sceneRoot.childNodes.map({ $0 }) {
            contentNode.addChildNode(child)
        }
        sceneRoot.addChildNode(contentNode)

        removeDisabledModelNodes(in: contentNode, modelSpec: modelSpec)
        applyBodyMaterials(in: contentNode, modelSpec: modelSpec, tintColor: bodyTintColor, bodyMaterial: bodyMaterial)
        applyScreenTexture(in: contentNode, modelSpec: modelSpec, screenshotImage: screenshotImage)

        let bounds = contentNode.boundingBox
        let sizeY = bounds.max.y - bounds.min.y
        let scale = sizeY > 0 ? modelSpec.targetBodyHeight / sizeY : 1
        contentNode.scale = SCNVector3(scale, scale, scale)
        contentNode.position = SCNVector3(
            -((bounds.min.x + bounds.max.x) / 2) * scale,
            -((bounds.min.y + bounds.max.y) / 2) * scale,
            -((bounds.min.z + bounds.max.z) / 2) * scale
        )

        let orientationNode = SCNNode()
        orientationNode.eulerAngles.z = frame.isLandscape ? .pi / 2 : 0
        orientationNode.eulerAngles.y = CGFloat((modelSpec.baseYawDegrees * .pi) / 180)
        orientationNode.addChildNode(contentNode)

        let presentationNode = SCNNode()
        presentationNode.eulerAngles = SCNVector3(
            Float((pitch * .pi) / 180),
            Float((yaw * .pi) / 180),
            0
        )
        presentationNode.addChildNode(orientationNode)
        sceneRoot.addChildNode(presentationNode)

        let camera = SCNCamera()
        camera.fieldOfView = 22
        camera.wantsDepthOfField = false
        camera.wantsHDR = true
        camera.zNear = 0.1
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.name = "deviceModelCamera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, Float(modelSpec.cameraDistance))
        sceneRoot.addChildNode(cameraNode)

        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = CGFloat(lighting.resolvedAmbientIntensity)
        ambientLight.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        sceneRoot.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .omni
        keyLight.intensity = CGFloat(lighting.resolvedKeyIntensity)
        keyLight.color = NSColor.white
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(-1.8, 2.4, 4.6)
        sceneRoot.addChildNode(keyNode)

        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = CGFloat(lighting.resolvedRimIntensity)
        rimLight.color = NSColor.white.withAlphaComponent(0.9)
        let rimNode = SCNNode()
        rimNode.light = rimLight
        rimNode.eulerAngles = SCNVector3(
            Float((-15.0 * Double.pi) / 180.0),
            Float((35.0 * Double.pi) / 180.0),
            0
        )
        sceneRoot.addChildNode(rimNode)

        fitModelToViewport(
            presentationNode: presentationNode,
            cameraNode: cameraNode,
            scene: scene,
            viewportSize: viewportSize
        )

        return (scene, cameraNode)
    }

    private static func fitModelToViewport(
        presentationNode: SCNNode,
        cameraNode: SCNNode,
        scene: SCNScene,
        viewportSize: CGSize
    ) {
        guard viewportSize.width > 1, viewportSize.height > 1,
              let camera = cameraNode.camera else { return }

        let cameraZ = CGFloat(cameraNode.position.z)
        guard cameraZ > 0 else { return }

        let fovRadians = camera.fieldOfView * .pi / 180
        let visibleHeight = 2 * cameraZ * tan(fovRadians / 2)
        let aspect = viewportSize.width / viewportSize.height
        let visibleWidth = visibleHeight * aspect

        let insetFactor: CGFloat = 0.9
        let availableWidth = visibleWidth * insetFactor
        let availableHeight = visibleHeight * insetFactor

        let bounds = worldBounds(of: presentationNode)
        let modelWidth = CGFloat(bounds.max.x - bounds.min.x)
        let modelHeight = CGFloat(bounds.max.y - bounds.min.y)

        guard modelWidth > 0.001, modelHeight > 0.001 else { return }

        let scaleFactor = min(
            availableWidth / modelWidth,
            availableHeight / modelHeight
        )

        if scaleFactor.isFinite, scaleFactor > 0, abs(scaleFactor - 1) > 0.01 {
            presentationNode.scale = SCNVector3(
                presentationNode.scale.x * scaleFactor,
                presentationNode.scale.y * scaleFactor,
                presentationNode.scale.z * scaleFactor
            )
        }

        let scaledBounds = worldBounds(of: presentationNode)
        let centerX = CGFloat(scaledBounds.min.x + scaledBounds.max.x) / 2
        let centerY = CGFloat(scaledBounds.min.y + scaledBounds.max.y) / 2
        presentationNode.position.x -= centerX
        presentationNode.position.y -= centerY
    }

    private static func clonedBaseScene(for modelSpec: DeviceFrameModelSpec) -> SCNScene? {
        let cacheKey = "\(modelSpec.resourceSubdirectory ?? "")/\(modelSpec.resourceName).\(modelSpec.resourceExtension)" as NSString
        let baseScene: SCNScene
        if let cached = modelSceneCache.object(forKey: cacheKey) {
            baseScene = cached
        } else {
            guard let url = Bundle.main.url(
                forResource: modelSpec.resourceName,
                withExtension: modelSpec.resourceExtension,
                subdirectory: modelSpec.resourceSubdirectory
            ) ?? Bundle.main.url(forResource: modelSpec.resourceName, withExtension: modelSpec.resourceExtension) else {
                return nil
            }
            guard let loadedScene = try? SCNScene(url: url, options: nil) else {
                return nil
            }
            modelSceneCache.setObject(loadedScene, forKey: cacheKey)
            baseScene = loadedScene
        }

        let clonedScene = SCNScene()
        for child in baseScene.rootNode.childNodes {
            clonedScene.rootNode.addChildNode(child.clone())
        }
        return clonedScene
    }

    private static func applyScreenTexture(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        screenshotImage: NSImage?
    ) {
        switch modelSpec.screenRenderingMode {
        case .replaceMaterial:
            applyScreenReplacementMaterial(in: contentNode, modelSpec: modelSpec, screenshotImage: screenshotImage)
        case .overlayPlane:
            applyScreenOverlayPlane(in: contentNode, modelSpec: modelSpec, screenshotImage: screenshotImage)
        }
    }

    private static func applyBodyMaterials(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        tintColor: NSColor? = nil,
        bodyMaterial: DeviceBodyMaterial
    ) {
        let isGlossy = bodyMaterial.resolvedFinish == .glossy
        let metalness = CGFloat(bodyMaterial.resolvedMetalness)
        let roughness = CGFloat(bodyMaterial.resolvedRoughness)

        enumerateNodes(in: contentNode) { node in
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

    private static func removeDisabledModelNodes(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec
    ) {
        guard !modelSpec.disabledNodeNames.isEmpty else { return }

        var nodesToRemove: [SCNNode] = []
        enumerateNodes(in: contentNode) { node in
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
        screenshotImage: NSImage?
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

        let screenContents = preparedScreenContents(from: screenshotImage)
        let materials = remappedGeometry.materials.map { material -> SCNMaterial in
            guard material.name == modelSpec.screenMaterialName else {
                return material.copy() as? SCNMaterial ?? SCNMaterial()
            }

            let replacement = material.copy() as? SCNMaterial ?? SCNMaterial()
            replacement.name = material.name
            let rot90 = screenTexture90CWTransform
            for prop in [replacement.diffuse, replacement.ambient, replacement.emission] {
                prop.contents = screenContents
                prop.contentsTransform = rot90
                prop.wrapS = .clamp
                prop.wrapT = .clamp
            }
            replacement.multiply.contents = NSColor.white
            replacement.transparent.contents = NSColor.white
            replacement.reflective.contents = NSColor.black
            replacement.metalness.contents = 0.0
            replacement.roughness.contents = 1.0
            replacement.normal.contents = NSColor.black
            replacement.lightingModel = .constant
            replacement.locksAmbientWithDiffuse = true
            replacement.isDoubleSided = true
            replacement.writesToDepthBuffer = true
            replacement.readsFromDepthBuffer = true
            return replacement
        }
        remappedGeometry.materials = materials
        screenNode.geometry = remappedGeometry
    }

    private static func applyScreenOverlayPlane(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        screenshotImage: NSImage?
    ) {
        guard let screenNode = findScreenNode(in: contentNode, modelSpec: modelSpec) else {
            return
        }

        let bounds = worldBounds(of: screenNode)
        let screenWidth = CGFloat(bounds.max.x - bounds.min.x)
        let screenHeight = CGFloat(bounds.max.y - bounds.min.y)
        guard screenWidth > 0.001, screenHeight > 0.001 else {
            return
        }

        let plane = SCNPlane(width: screenWidth, height: screenHeight)
        plane.cornerRadius = min(screenWidth / 2, screenHeight * 0.075)

        let material = SCNMaterial()
        material.name = "ScreenOverlay"
        let screenContents = preparedScreenContents(from: screenshotImage)
        for prop in [material.diffuse, material.ambient, material.emission] {
            prop.contents = screenContents
            prop.wrapS = .clamp
            prop.wrapT = .clamp
        }
        material.multiply.contents = NSColor.white
        material.transparent.contents = NSColor.white
        material.reflective.contents = NSColor.black
        material.metalness.contents = 0.0
        material.roughness.contents = 1.0
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        plane.materials = [material]

        let centerInWorld = SCNVector3(
            (bounds.min.x + bounds.max.x) / 2,
            (bounds.min.y + bounds.max.y) / 2,
            bounds.max.z + 0.001
        )
        let centerInContent = contentNode.convertPosition(centerInWorld, from: nil)

        let planeNode = SCNNode(geometry: plane)
        planeNode.name = "screenTextureOverlay"
        planeNode.position = centerInContent
        contentNode.addChildNode(planeNode)
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

    private static func preparedScreenContents(from image: NSImage?) -> Any {
        guard let image else { return NSColor.white }
        if let cgImage = normalizedScreenCGImage(from: image) {
            return cgImage
        }
        return image
    }

    private static func normalizedScreenCGImage(from image: NSImage) -> CGImage? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let width = source.width
        let height = source.height
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .high
        context.draw(source, in: rect)
        return context.makeImage()
    }

    private static func findScreenNode(in root: SCNNode, modelSpec: DeviceFrameModelSpec) -> SCNNode? {
        if let screenMaterialName = modelSpec.screenMaterialName,
           let node = findNode(in: root, matchingMaterialNamed: screenMaterialName) {
            return node
        }

        let frontZ = root.boundingBox.max.z
        var candidate: (node: SCNNode, area: CGFloat)?
        enumerateNodes(in: root) { node in
            guard let geometry = node.geometry else { return }
            let bounds = geometry.boundingBox
            let dx = bounds.max.x - bounds.min.x
            let dy = bounds.max.y - bounds.min.y
            let dz = bounds.max.z - bounds.min.z
            guard dx > 0, dy > 0, dz < 1 else { return }
            let worldBounds = worldBounds(of: node)
            let distanceFromFront = abs(worldBounds.max.z - frontZ)
            guard distanceFromFront < 2 else { return }
            let area = dx * dy
            if candidate == nil || area > candidate?.area ?? 0 {
                candidate = (node, area)
            }
        }
        return candidate?.node
    }

    private static func findNode(in root: SCNNode, matchingMaterialNamed materialName: String) -> SCNNode? {
        if let geometry = root.geometry,
           geometry.materials.contains(where: { $0.name == materialName }) {
            return root
        }
        for child in root.childNodes {
            if let match = findNode(in: child, matchingMaterialNamed: materialName) {
                return match
            }
        }
        return nil
    }

    private static func enumerateNodes(in root: SCNNode, visit: (SCNNode) -> Void) {
        visit(root)
        for child in root.childNodes {
            enumerateNodes(in: child, visit: visit)
        }
    }

    private static func worldBounds(of node: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        var accumulated: (min: SCNVector3, max: SCNVector3)?

        if let geometry = node.geometry {
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
            ].map { node.convertPosition($0, to: nil) }

            accumulated = boundsCovering(points: corners)
        }

        for child in node.childNodes {
            let childBounds = worldBounds(of: child)
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

    private static func boundsCovering(points: [SCNVector3]) -> (min: SCNVector3, max: SCNVector3) {
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
