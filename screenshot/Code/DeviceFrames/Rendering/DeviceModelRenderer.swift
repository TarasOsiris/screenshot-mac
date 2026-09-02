#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Metal
import os
import SceneKit
import SwiftUI

// SCNVector3 components are CGFloat on macOS but Float on iOS.
#if os(macOS)
typealias SCNFloat = CGFloat
#else
typealias SCNFloat = Float
#endif

/// SceneKit rendering for 3D device frames: builds and caches the scene, renders a snapshot, and
/// caches the resulting image.
///
/// These were all static members of `DeviceModelFrameView`, which made one 973-line `View` struct
/// also the scene builder, both caches and the cache-key model. None of it needs a view.
nonisolated enum DeviceModelRenderer {
    /// Shared by every `NSCache` holding decoded device-frame bitmaps (snapshots here, bezel PNGs
    /// in `DeviceFrameImageView`) — one bound on how much decoded-pixel memory those caches keep.
    static let decodedImageCacheByteLimit = 256 * 1024 * 1024
    private static let modelSnapshotScale: CGFloat = 3
    private static let exportSnapshotPixelBudget: CGFloat = 4096
    /// Ceiling on an editor snapshot's long edge. A 450 pt device on a 2× display needs 900 px;
    /// 1024 keeps headroom above retina without rasterizing the 1350 px a blanket 3× asks for.
    static let editorSnapshotMaxEdge: CGFloat = 1024
    /// Rung width for that long edge. The pixel box lands in `SnapshotKey.cacheKey`, and `width`
    /// and `height` here already contain `displayScale(zoom:)` — so a continuous value would miss
    /// the cache on every pinch tick and pay a full SceneKit render per device per frame.
    /// Quantizing the *scale* would not help; the pixel box is what the key holds.
    static let editorSnapshotEdgeStep: CGFloat = 128

    /// The snapshot's pixel dimensions. The one place that answers this, so the editor and the
    /// exporter cannot drift apart on it.
    ///
    /// Export is unchanged: 3× capped to a 4096 budget, because shapes are already at model
    /// resolution there and a blanket 3× would rasterize ~9× the pixels needed. The editor caps
    /// and quantizes instead — above ~341 pt on screen a device is pinned at 1024 px for every
    /// zoom level, which turns zooming into a cache hit.
    static func snapshotPixelSize(width: CGFloat, height: CGFloat, isExport: Bool) -> CGSize {
        let safeWidth = max(1, width)
        let safeHeight = max(1, height)
        let longest = max(safeWidth, safeHeight)

        if isExport {
            let scale = min(modelSnapshotScale, max(1, exportSnapshotPixelBudget / longest))
            return CGSize(
                width: max(1, (safeWidth * scale).rounded(.up)),
                height: max(1, (safeHeight * scale).rounded(.up))
            )
        }

        let requested = min(longest * modelSnapshotScale, editorSnapshotMaxEdge)
        let rungs = (requested / editorSnapshotEdgeStep).rounded(.up)
        let quantizedLong = max(editorSnapshotEdgeStep, rungs * editorSnapshotEdgeStep)
        // Derived from the shape's aspect ratio, which is zoom-independent, so the box stays put
        // as the user zooms. Matching the aspect also keeps `fitModelToViewport` from stretching.
        let shortEdge = max(1, (quantizedLong * (min(safeWidth, safeHeight) / longest)).rounded())
        return safeWidth >= safeHeight
            ? CGSize(width: quantizedLong, height: shortEdge)
            : CGSize(width: shortEdge, height: quantizedLong)
    }
    private static let snapshotExposureOffset: CGFloat = -0.7
    nonisolated(unsafe) private static let snapshotImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 160
        cache.totalCostLimit = decodedImageCacheByteLimit
        return cache
    }()
    /// Also the cap on how many specs `DeviceModelSnapshotQueue.prewarm` will warm: warming more
    /// than the cache holds evicts the early ones before anything asks for them.
    static let modelSceneCacheLimit = 4
    nonisolated(unsafe) private static let modelSceneCache: NSCache<NSString, SCNScene> = {
        let cache = NSCache<NSString, SCNScene>()
        cache.countLimit = modelSceneCacheLimit
        return cache
    }()

    /// Guards the cached base scenes. `clonedBaseScene` is reachable from two executors at once —
    /// `DeviceModelSnapshotQueue` (editor snapshots, prewarm) and the main actor (export's
    /// `synchronousSnapshot`, `LiveDeviceModelView`) — and `NSCache` locking its own storage does
    /// not make the `SCNScene` it hands back safe to read concurrently: `child.clone()` walks a
    /// shared node graph whose bounding boxes SceneKit memoizes lazily, so a first touch from two
    /// threads is a race. One lock rather than a cache per executor, which would double the parse
    /// and still leave export and the queue sharing one.
    nonisolated(unsafe) private static let sceneCacheLock = NSLock()

    /// Guards the GPU pass itself, for the same two executors. `DeviceModelSnapshotQueue` serializes
    /// only its own callers, and export renders straight from the main actor — so without this two
    /// `SCNRenderer`s submit 4×-MSAA passes to one `MTLDevice` at once, which is where the blank
    /// snapshots the retry below papers over come from. Taken after `makeDeviceModelScene` has
    /// released `sceneCacheLock`, so the two never nest.
    nonisolated(unsafe) private static let gpuRenderLock = NSLock()
    nonisolated(unsafe) private static let screenTextureCache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 16
        cache.totalCostLimit = decodedImageCacheByteLimit
        return cache
    }()
    /// One device across all snapshots keeps Metal's compiled-shader cache warm between renders.
    nonisolated(unsafe) static let sharedMetalDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()

    struct SnapshotKey: Hashable {
        let frameId: String
        /// Only `.export` renders may share an entry with an export. The other two draw the
        /// editor's screenshots — downsamples `EditorImagePresentation` already moved to sRGB —
        /// and below ~1200 px one of those shares both its file name and its pixel size with the
        /// untouched PNG export loads. A canvas raster collides when the 128 px rung lands on
        /// `ceil(points × 3)`; a project card collides outright, since it rasterizes at the same
        /// export pixel budget. Either would let a colour-converted texture define exported bytes.
        let renderContext: RasterRenderContext
        let pixelWidth: Int
        let pixelHeight: Int
        let hasScreenshot: Bool
        let screenshotIdentity: String?
        let screenshotWidth: Int
        let screenshotHeight: Int
        let pitch: Int
        let yaw: Int
        let materialFinish: String
        let ambient: Int
        let key: Int
        let rim: Int
        let bodyColor: String

        /// A screenshot with no stable identity can't be told apart from any other, so it
        /// must re-render rather than risk serving a different shape's snapshot.
        var isCacheable: Bool { !hasScreenshot || screenshotIdentity != nil }

        /// `frameId` carries the model, colourway and orientation, so a raster of the same one is the
        /// same silhouette — every other field settles within a render or two, and the fallback the
        /// view would show instead has no pose at all.
        func canStandInFor(_ other: Self) -> Bool {
            frameId == other.frameId
        }

        /// Only the raster resolution differs, which is the signature of a zoom step — the one change
        /// worth making a render wait, because it re-keys every device in the row at once.
        func matchesIgnoringPixelSize(_ other: Self) -> Bool {
            frameId == other.frameId
                && renderContext == other.renderContext
                && hasScreenshot == other.hasScreenshot
                && screenshotIdentity == other.screenshotIdentity
                && screenshotWidth == other.screenshotWidth
                && screenshotHeight == other.screenshotHeight
                && pitch == other.pitch
                && yaw == other.yaw
                && materialFinish == other.materialFinish
                && ambient == other.ambient
                && key == other.key
                && rim == other.rim
                && bodyColor == other.bodyColor
        }

        var cacheKey: NSString {
            [
                frameId,
                renderContext.rawValue,
                "\(pixelWidth)x\(pixelHeight)",
                screenshotIdentity ?? "no-image",
                "\(screenshotWidth)x\(screenshotHeight)",
                "p\(pitch)",
                "y\(yaw)",
                materialFinish,
                "a\(ambient)",
                "k\(key)",
                "r\(rim)",
                bodyColor
            ].joined(separator: "|") as NSString
        }
    }
    static func cachedSnapshot(for key: SnapshotKey) -> NSImage? {
        guard key.isCacheable else { return nil }
        return snapshotImageCache.object(forKey: key.cacheKey)
    }

    static func storeSnapshot(_ image: NSImage, for key: SnapshotKey) {
        guard key.isCacheable else { return }
        snapshotImageCache.setObject(image, forKey: key.cacheKey, cost: key.pixelWidth * key.pixelHeight * 4)
    }

    static func snapshotKey(
        frame: DeviceFrame,
        renderContext: RasterRenderContext,
        pixelSize: CGSize,
        screenshotImage: NSImage?,
        screenshotImageIdentity: String?,
        pitch: Double,
        yaw: Double,
        bodyMaterial: DeviceBodyMaterial,
        lighting: DeviceLighting,
        bodyColor: Color
    ) -> SnapshotKey {
        let imageSize = screenshotImage?.size ?? .zero
        let color = bodyColor.sRGBComponents
        let angleStep = renderContext == .canvas ? snapshotAngleStep : snapshotFineStep
        return SnapshotKey(
            frameId: frame.id,
            renderContext: renderContext,
            pixelWidth: max(1, Int(pixelSize.width.rounded(.up))),
            pixelHeight: max(1, Int(pixelSize.height.rounded(.up))),
            hasScreenshot: screenshotImage != nil,
            screenshotIdentity: screenshotImage == nil ? nil : screenshotImageIdentity,
            screenshotWidth: max(0, Int(imageSize.width.rounded())),
            screenshotHeight: max(0, Int(imageSize.height.rounded())),
            pitch: quantized(pitch, step: angleStep),
            yaw: quantized(yaw, step: angleStep),
            materialFinish: bodyMaterial.resolvedFinish.rawValue,
            ambient: quantized(lighting.resolvedAmbientIntensity),
            key: quantized(lighting.resolvedKeyIntensity),
            rim: quantized(lighting.resolvedRimIntensity),
            bodyColor: "\(quantized(Double(color.r)))-\(quantized(Double(color.g)))-\(quantized(Double(color.b)))-\(quantized(Double(color.a)))"
        )
    }

    /// The rung every key field uses by default, and the one export's pose angles keep.
    static let snapshotFineStep: Double = 0.001

    private static func quantized(_ value: Double, step: Double = snapshotFineStep) -> Int {
        Int((value / step).rounded())
    }

    /// Pose angles get a much coarser rung than the other key fields — **on the canvas only**. A
    /// rotation slider sweeps ~0.9°/pt, so the fine step made every mouse position a distinct cache
    /// entry: jitter never deduped and one sweep evicted the whole 160-entry cache. A quarter of a
    /// degree is well under a pixel of silhouette movement at the 1024 px canvas cap, but it is
    /// ~4 px at the 4096 px offscreen budget — and two deliberately different poses must never
    /// export pixel-identical.
    static let snapshotAngleStep: Double = 0.25

    /// Renders one device model offscreen.
    ///
    /// `nonisolated` and **synchronous** on purpose, so it carries no executor semantics of its own:
    /// the exporter calls it directly on the main actor inside a single rasterization pass, and the
    /// editor calls it from `DeviceModelSnapshotQueue`, which really does leave the main thread.
    /// One implementation, two callers, no way for them to drift.
    ///
    /// Returns a `CGImage` rather than an `NSImage` because the caller wraps it back up on its own
    /// actor — `NSImage` is not `Sendable`, and the old code *mutated* the returned image's `size`
    /// after producing it, which is exactly the shape Sendability exists to stop.
    static func snapshotDeviceModel(
        _ request: DeviceModelSnapshotRequest,
        using existingRenderer: SCNRenderer? = nil
    ) -> CGImage? {
        let viewportSize = request.pixelSize
        let signpost = PerfSignpost.begin(
            "DeviceModelRenderer.snapshot",
            pixels: Int(viewportSize.width * viewportSize.height)
        )
        defer { PerfSignpost.end("DeviceModelRenderer.snapshot", signpost) }

        guard let (scene, cameraNode) = makeDeviceModelScene(
            frame: request.frame,
            viewportSize: viewportSize,
            screenContents: request.screenContents,
            screenContentsIdentity: request.screenContentsIdentity,
            pitch: request.pitch,
            yaw: request.yaw,
            bodyMaterial: request.bodyMaterial,
            lighting: request.lighting,
            bodyTintColor: request.bodyTint?.platformColor
        ) else {
            AppLogger.export.warning(
                "Device model scene unavailable for frame \(request.frame.id, privacy: .public)"
            )
            return nil
        }

        let renderer = existingRenderer ?? SCNRenderer(device: sharedMetalDevice, options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        // A reused renderer would otherwise hold this scene alive until the next render.
        defer {
            renderer.scene = nil
            renderer.pointOfView = nil
        }
        if let camera = cameraNode.camera {
            camera.wantsExposureAdaptation = false
            camera.exposureOffset = .init(snapshotExposureOffset)
        }
        gpuRenderLock.lock()
        defer { gpuRenderLock.unlock() }

        // Forces shader compilation and texture upload before the one-shot snapshot, which
        // otherwise has no frame to recover on if the scene isn't GPU-resident yet.
        let prepareSpan = PerfSignpost.begin("DeviceModelRenderer.prepare")
        renderer.prepare(scene, shouldAbortBlock: nil)
        PerfSignpost.end("DeviceModelRenderer.prepare", prepareSpan)

        guard var image = renderedCGImage(renderer, viewportSize: viewportSize) else { return nil }
        if isBlank(image) {
            // The retry doubles the cost of the whole snapshot and is otherwise invisible.
            PerfSignpost.event("DeviceModelRenderer.blankRetry")
            guard let retry = renderedCGImage(renderer, viewportSize: viewportSize), !isBlank(retry) else {
                AppLogger.export.warning(
                    "Device model snapshot came back blank for frame \(request.frame.id, privacy: .public)"
                )
                return nil
            }
            image = retry
        }
        return image
    }

    private static func renderedCGImage(_ renderer: SCNRenderer, viewportSize: CGSize) -> CGImage? {
        let image = renderer.snapshot(atTime: 0, with: viewportSize, antialiasingMode: .multisampling4X)
        #if os(macOS)
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    /// True when every sampled pixel is fully transparent. A blank snapshot is indistinguishable
    /// from a valid one downstream, so it has to be caught here or the device vanishes silently.
    private static func isBlank(_ cgImage: CGImage) -> Bool {
        let sampleCount = 32
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return true }

        var alpha = [UInt8](repeating: 0, count: sampleCount * sampleCount)
        guard let context = CGContext(
            data: &alpha,
            width: sampleCount,
            height: sampleCount,
            bitsPerComponent: 8,
            bytesPerRow: sampleCount,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleCount, height: sampleCount))
        return alpha.allSatisfy { $0 == 0 }
    }

    static func makeDeviceModelScene(
        frame: DeviceFrame,
        viewportSize: CGSize,
        screenContents: CGImage?,
        screenContentsIdentity: String? = nil,
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
        applyScreenTexture(
            in: contentNode,
            modelSpec: modelSpec,
            screenContents: screenContents,
            screenContentsIdentity: screenContentsIdentity
        )

        let bounds = contentNode.boundingBox
        let sizeY = bounds.max.y - bounds.min.y
        let scale: SCNFloat = sizeY > 0 ? SCNFloat(modelSpec.targetBodyHeight) / sizeY : 1
        contentNode.scale = SCNVector3(scale, scale, scale)
        contentNode.position = SCNVector3(
            -((bounds.min.x + bounds.max.x) / 2) * scale,
            -((bounds.min.y + bounds.max.y) / 2) * scale,
            -((bounds.min.z + bounds.max.z) / 2) * scale
        )

        let orientationNode = SCNNode()
        orientationNode.eulerAngles.z = frame.isLandscape ? .pi / 2 : 0
        orientationNode.eulerAngles.y = SCNFloat((modelSpec.baseYawDegrees * .pi) / 180)
        orientationNode.addChildNode(contentNode)

        let presentationNode = SCNNode()
        presentationNode.name = "deviceModelPresentation"
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

    /// Re-fit an already-built scene to a new viewport size WITHOUT rebuilding
    /// geometry/materials. The presentation node's scale/position are reset to
    /// their pre-fit identity values first so the fit stays idempotent across
    /// repeated resize callbacks.
    static func refitDeviceModelScene(
        _ scene: SCNScene,
        cameraNode: SCNNode,
        viewportSize: CGSize
    ) {
        guard let presentationNode = scene.rootNode.childNode(
            withName: "deviceModelPresentation",
            recursively: true
        ) else { return }
        presentationNode.scale = SCNVector3(1, 1, 1)
        presentationNode.position = SCNVector3(0, 0, 0)
        fitModelToViewport(
            presentationNode: presentationNode,
            cameraNode: cameraNode,
            scene: scene,
            viewportSize: viewportSize
        )
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
            let factor = SCNFloat(scaleFactor)
            presentationNode.scale = SCNVector3(
                presentationNode.scale.x * factor,
                presentationNode.scale.y * factor,
                presentationNode.scale.z * factor
            )
        }

        let scaledBounds = worldBounds(of: presentationNode)
        let centerX = SCNFloat(scaledBounds.min.x + scaledBounds.max.x) / 2
        let centerY = SCNFloat(scaledBounds.min.y + scaledBounds.max.y) / 2
        presentationNode.position.x -= centerX
        presentationNode.position.y -= centerY
    }

    /// Loads a model into the shared scene cache without rendering anything.
    static func prewarmModelScene(for modelSpec: DeviceFrameModelSpec) {
        _ = clonedBaseScene(for: modelSpec)
    }

    private static func clonedBaseScene(for modelSpec: DeviceFrameModelSpec) -> SCNScene? {
        let span = PerfSignpost.begin("DeviceModelRenderer.loadScene")
        defer { PerfSignpost.end("DeviceModelRenderer.loadScene", span) }
        // Held across the clone too, not just the cache lookup — the clone is the shared read.
        sceneCacheLock.lock()
        defer { sceneCacheLock.unlock() }
        let cacheKey = "\(modelSpec.resourceName).\(modelSpec.resourceExtension)" as NSString
        let baseScene: SCNScene
        if let cached = modelSceneCache.object(forKey: cacheKey) {
            baseScene = cached
        } else {
            guard let url = Bundle.main.url(
                forResource: modelSpec.resourceName,
                withExtension: modelSpec.resourceExtension
            ) else {
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
        screenContents: Any
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

    private static func preparedScreenContents(from contents: CGImage?, identity: String?) -> Any {
        guard let contents else { return NSColor.white }
        return normalizedScreenContents(contents, identity: identity) ?? contents
    }

    /// `normalizedScreenCGImage` redraws the whole screenshot, and a rotation drag asks for the same
    /// one every tick. Editor-only by construction — `DeviceModelSnapshotRequest.make` withholds the
    /// identity on export, whose raster differs from the editor's thumbnail in colour but not always
    /// in size. The size still rides in the key so a second caller can't reintroduce that collision.
    static func normalizedScreenContents(_ source: CGImage, identity: String?) -> CGImage? {
        guard let identity else { return normalizedScreenCGImage(from: source) }
        let cacheKey = "\(identity)|\(source.width)x\(source.height)" as NSString
        if let cached = screenTextureCache.object(forKey: cacheKey) { return cached }
        guard let normalized = normalizedScreenCGImage(from: source) else { return nil }
        screenTextureCache.setObject(normalized, forKey: cacheKey, cost: normalized.width * normalized.height * 4)
        return normalized
    }

    /// The caller's actor pulls the `CGImage` off the non-`Sendable` `NSImage`; this redraw — a
    /// full-size `CGContext.draw` — is the half that runs on the render executor.
    static func screenContents(from image: NSImage?) -> CGImage? {
        guard let image else { return nil }
        #if os(macOS)
        if let direct = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { return direct }
        #else
        if let direct = image.cgImage { return direct }
        #endif
        // An image with no bitmap representation (vector- or PDF-backed) used to be handed to
        // SceneKit whole and rasterized there. It can't cross to the render executor, so rasterize
        // it here instead — otherwise `preparedScreenContents` falls through to white and the
        // device renders a blank screen, silently, in export as well as the editor.
        return rasterizedScreenContents(from: image)
    }

    private static func rasterizedScreenContents(from image: NSImage) -> CGImage? {
        let width = max(1, Int(image.size.width.rounded()))
        let height = max(1, Int(image.size.height.rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        #if os(macOS)
        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        #else
        UIGraphicsPushContext(context)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        image.draw(in: rect)
        UIGraphicsPopContext()
        #endif
        return context.makeImage()
    }

    private static func normalizedScreenCGImage(from source: CGImage) -> CGImage? {
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
        var candidate: (node: SCNNode, area: SCNFloat)?
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
