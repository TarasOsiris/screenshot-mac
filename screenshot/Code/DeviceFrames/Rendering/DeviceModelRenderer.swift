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
    private static let cameraExposureOffset: CGFloat = -0.7
    /// Cancels the camera exposure so the screenshot renders at its source colours.
    static let screenEmissionIntensity: CGFloat = pow(2, -cameraExposureOffset)
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
    /// One device across all snapshots keeps Metal's compiled-shader cache warm between renders.
    nonisolated(unsafe) static let sharedMetalDevice: (any MTLDevice)? = MTLCreateSystemDefaultDevice()

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
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = .init(cameraExposureOffset)
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

        let bounds = presentationNode.worldBounds()
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

        let scaledBounds = presentationNode.worldBounds()
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
}
