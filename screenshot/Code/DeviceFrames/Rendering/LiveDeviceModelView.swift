import AppKit
import SceneKit
import SwiftUI

struct LiveDeviceModelView: NSViewRepresentable {
    let frame: DeviceFrame
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?
    let pitch: Double
    let yaw: Double
    let bodyMaterial: DeviceBodyMaterial
    let lighting: DeviceLighting
    let bodyTintColor: NSColor?

    /// Identity of every input that affects the scene's geometry/materials —
    /// i.e. everything EXCEPT the viewport size. When this is unchanged, a size
    /// change only needs a camera re-fit, not a full scene rebuild.
    struct SceneSignature: Equatable {
        let frame: DeviceFrame
        let screenshot: ObjectIdentifier?
        let pitch: Double
        let yaw: Double
        let bodyMaterial: DeviceBodyMaterial
        let lighting: DeviceLighting
        let bodyTintColor: NSColor?
    }

    private var sceneSignature: SceneSignature {
        SceneSignature(
            frame: frame,
            screenshot: screenshotImage.map(ObjectIdentifier.init),
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTintColor: bodyTintColor
        )
    }

    final class Coordinator {
        var lastSignature: SceneSignature?
        var lastViewport: CGSize?
        weak var cameraNode: SCNNode?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let scnView = RetinaSCNView(frame: NSRect(x: 0, y: 0, width: max(1, width), height: max(1, height)))
        scnView.backgroundColor = .clear
        scnView.wantsLayer = true
        let initialScale = NSScreen.main?.backingScaleFactor ?? 2.0
        scnView.layer?.contentsScale = max(2.0, initialScale)
        scnView.layer?.isOpaque = false
        scnView.layerContentsRedrawPolicy = .duringViewResize
        scnView.antialiasingMode = .multisampling4X
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = false
        scnView.isJitteringEnabled = false
        scnView.preferredFramesPerSecond = 60
        update(scnView, coordinator: context.coordinator)
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let currentScale = nsView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        nsView.layer?.contentsScale = max(2.0, currentScale)
        update(nsView, coordinator: context.coordinator)
        nsView.needsDisplay = true
    }

    static func dismantleNSView(_ nsView: SCNView, coordinator: Coordinator) {
        nsView.isPlaying = false
        nsView.scene = nil
        nsView.pointOfView = nil
        coordinator.cameraNode = nil
        coordinator.lastSignature = nil
        coordinator.lastViewport = nil
    }

    private func update(_ scnView: SCNView, coordinator: Coordinator) {
        let viewport = CGSize(width: max(1, width), height: max(1, height))
        let signature = sceneSignature

        if coordinator.lastSignature == signature,
           let existingScene = scnView.scene,
           let cameraNode = coordinator.cameraNode {
            // Geometry/materials unchanged — only re-fit if the viewport changed.
            if coordinator.lastViewport != viewport {
                DeviceModelFrameView.refitDeviceModelScene(
                    existingScene,
                    cameraNode: cameraNode,
                    viewportSize: viewport
                )
                coordinator.lastViewport = viewport
            }
            scnView.frame = NSRect(origin: .zero, size: viewport)
            return
        }

        guard let (scene, cameraNode) = DeviceModelFrameView.makeDeviceModelScene(
            frame: frame,
            viewportSize: viewport,
            screenshotImage: screenshotImage,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTintColor: bodyTintColor
        ) else {
            return
        }
        scnView.scene = scene
        scnView.pointOfView = cameraNode
        scnView.frame = NSRect(origin: .zero, size: viewport)
        coordinator.lastSignature = signature
        coordinator.lastViewport = viewport
        coordinator.cameraNode = cameraNode
    }
}

private final class RetinaSCNView: SCNView {
    private var lastScale: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateBackingScale()
    }

    override func layout() {
        super.layout()
        updateBackingScale()
    }

    private func updateBackingScale() {
        let screenScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let scale = max(2.0, screenScale)
        if layer?.contentsScale != scale || lastScale != scale {
            layer?.contentsScale = scale
            lastScale = scale
            needsDisplay = true
        }
    }
}
