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
        update(scnView)
        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        let currentScale = nsView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        nsView.layer?.contentsScale = max(2.0, currentScale)
        update(nsView)
        nsView.needsDisplay = true
    }

    private func update(_ scnView: SCNView) {
        guard let (scene, cameraNode) = DeviceModelFrameView.makeDeviceModelScene(
            frame: frame,
            viewportSize: CGSize(width: max(1, width), height: max(1, height)),
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
        scnView.frame = NSRect(x: 0, y: 0, width: max(1, width), height: max(1, height))
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
