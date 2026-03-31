import AppKit
import SceneKit
import SwiftUI

// Device frame rendering — image-based (real frames) or programmatic.
//
// iPhone 17 physical specs (mm):
//   Body: 149.6 H × 71.5 W × 7.95 D
//   Bezels: 1.44 top/bottom, 1.41 left/right
//   Display: 6.3" OLED, 2622 × 1206 px @ 460 ppi
//
// Base unit: 220 px width → scale factor 3.077 px/mm
// All dimensions derived from mm × 3.077

enum DeviceModelRenderingMode: Sendable {
    case snapshot
    case live
}

struct DeviceFrameView: View {
    private static let modelSnapshotScale: CGFloat = 3
    private static let snapshotExposureOffset: CGFloat = -0.7
    private static let frameImageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 50
        return cache
    }()
    private static let modelSceneCache: NSCache<NSString, SCNScene> = {
        let cache = NSCache<NSString, SCNScene>()
        cache.countLimit = 4
        return cache
    }()

    let category: DeviceCategory
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    var screenshotImage: NSImage? = nil
    /// When set, renders using a real PNG frame from the catalog instead of programmatic drawing.
    var deviceFrameId: String? = nil
    var devicePitch: Double = 0
    var deviceYaw: Double = 0
    var modelRenderingMode: DeviceModelRenderingMode = .snapshot

    private var scale: CGFloat {
        let base = category.baseDimensions
        return min(width / base.width, height / base.height)
    }

    var body: some View {
        if let frameId = deviceFrameId,
           let frame = DeviceFrameCatalog.frame(for: frameId),
           frame.isModelBacked {
            modelBackedFrame(frame: frame)
        } else if let frameId = deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            imageBasedFrame(frame: frame)
        } else {
            programmaticFrame
        }
    }

    @ViewBuilder
    private func modelBackedFrame(frame: DeviceFrame) -> some View {
        switch modelRenderingMode {
        case .live:
            LiveDeviceModelView(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                pitch: devicePitch,
                yaw: deviceYaw,
                bodyTintColor: NSColor(bodyColor)
            )
            .frame(width: width, height: height)
        case .snapshot:
            if let image = Self.snapshotDeviceModel(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                pitch: devicePitch,
                yaw: deviceYaw,
                bodyTintColor: NSColor(bodyColor)
            ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            } else {
                programmaticFrame
            }
        }
    }

    // MARK: - Image-Based Frame

    @ViewBuilder
    private func imageBasedFrame(frame: DeviceFrame) -> some View {
        let spec = frame.spec
        let frameImage = frame.imageName.flatMap(Self.cachedFrameImage(named:))

        ZStack(alignment: .topLeading) {
            // Screenshot placed at the screen area position
            Group {
                if let screenshotImage {
                    Image(nsImage: screenshotImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                } else {
                    Color.white
                }
            }
            .frame(
                width: width * (1 - spec.leftFraction - spec.rightFraction),
                height: height * (1 - spec.topFraction - spec.bottomFraction)
            )
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: height * spec.cornerRadiusFraction,
                bottomLeadingRadius: frame.fallbackCategory == .macbook ? 0 : height * spec.cornerRadiusFraction,
                bottomTrailingRadius: frame.fallbackCategory == .macbook ? 0 : height * spec.cornerRadiusFraction,
                topTrailingRadius: height * spec.cornerRadiusFraction,
                style: .continuous
            ))
            .offset(
                x: width * spec.leftFraction,
                y: height * spec.topFraction
            )

            // Frame overlay
            if let frameImage {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
    }

    private static func cachedFrameImage(named imageName: String) -> NSImage? {
        let key = imageName as NSString
        if let cached = frameImageCache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(named: imageName) else { return nil }
        frameImageCache.setObject(image, forKey: key)
        return image
    }

    // MARK: - Programmatic Frame

    @ViewBuilder
    private var programmaticFrame: some View {
        switch category {
        case .iphone:
            iPhoneFrame
        case .ipadPro11, .ipadPro13:
            iPadFrame
        case .macbook:
            macBookFrame
        case .androidPhone:
            androidPhoneFrame
        case .androidTablet:
            androidTabletFrame
        }
    }

    // MARK: - iPhone 17 Frame

    private var iPhoneFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = bodyH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        // Dynamic Island: ~126 × 37 pts @ 3x = 376 × 110 px on 1206 × 2622 display
        let diW: CGFloat = screenW * 0.312
        let diH: CGFloat = screenH * 0.042
        let diOffsetFromScreenTop: CGFloat = screenH * 0.016 + diH / 2

        // Home indicator: ~134 × 5 pts @ 3x = 402 × 15 px → 33.3% of screen W
        let homeW: CGFloat = screenW * 0.333
        let homeH: CGFloat = 2.5 * s
        let homeOffsetFromScreenBottom: CGFloat = 8 * s + homeH / 2

        // Button dimensions (protruding from body edge)
        let btnDepth: CGFloat = category.buttonDepth * s
        let btnColor = buttonColor

        // Left side buttons (Action + Volume Up + Volume Down)
        let actionH: CGFloat = 29 * s
        let actionY: CGFloat = bodyH * 0.35
        let volUpH: CGFloat = 34 * s
        let volUpY: CGFloat = bodyH * 0.44
        let volDownH: CGFloat = 34 * s
        let volDownY: CGFloat = bodyH * 0.54

        // Right side buttons
        let powerH: CGFloat = 46 * s
        let powerY: CGFloat = bodyH * 0.38
        let camCtrlH: CGFloat = 25 * s
        let camCtrlY: CGFloat = bodyH * 0.67

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        let totalW = bodyW + btnDepth * 2

        return ZStack {
            deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)
            screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)

            // Dynamic Island
            RoundedRectangle(cornerRadius: diH / 2, style: .continuous)
                .fill(.black)
                .frame(width: diW, height: diH)
                .overlay(
                    RoundedRectangle(cornerRadius: diH / 2, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5 * s)
                )
                .offset(y: -(screenH / 2 - diOffsetFromScreenTop))

            // Home indicator
            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: homeW, height: homeH)
                .offset(y: screenH / 2 - homeOffsetFromScreenBottom)

            // Left side buttons
            sideButton(width: btnDepth, height: actionH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - actionY))
            sideButton(width: btnDepth, height: volUpH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volUpY))
            sideButton(width: btnDepth, height: volDownH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volDownY))

            // Right side buttons
            sideButton(width: btnDepth, height: powerH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - powerY))
            sideButton(width: btnDepth * 0.7, height: camCtrlH, color: btnColor.opacity(0.7))
                .offset(x: bodyW / 2 + btnDepth * 0.35, y: -(bodyH / 2 - camCtrlY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: totalW, height: bodyH)
    }

    // MARK: - iPad Pro Frame

    private var iPadFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = bodyH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        // Front camera: small dot centered on top short edge
        let cameraD: CGFloat = 6 * s
        let cameraOffsetFromTop: CGFloat = bezelTB / 2

        // Power button on top edge (Touch ID)
        let powerW: CGFloat = 34 * s
        let powerH: CGFloat = 2.5 * s
        let powerOffsetX: CGFloat = bodyW * 0.35

        // Volume buttons on right edge
        let volBtnW: CGFloat = 2.5 * s
        let volUpH: CGFloat = 28 * s
        let volDownH: CGFloat = 28 * s
        let volUpY: CGFloat = bodyH * 0.28
        let volDownY: CGFloat = bodyH * 0.37

        let btnColor = buttonColor

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        return ZStack {
            deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)
            screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)

            // Front camera (small dot at top center)
            Circle()
                .fill(.black.opacity(0.35))
                .frame(width: cameraD, height: cameraD)
                .offset(y: -(bodyH / 2 - cameraOffsetFromTop))

            // Power/Touch ID button on top edge
            sideButton(width: powerW, height: powerH, color: btnColor)
                .offset(x: powerOffsetX, y: -(bodyH / 2 + powerH / 2))

            // Volume Up on right edge
            sideButton(width: volBtnW, height: volUpH, color: btnColor)
                .offset(x: bodyW / 2 + volBtnW / 2, y: -(bodyH / 2 - volUpY))

            // Volume Down on right edge
            sideButton(width: volBtnW, height: volDownH, color: btnColor)
                .offset(x: bodyW / 2 + volBtnW / 2, y: -(bodyH / 2 - volDownY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: bodyW, height: bodyH)
    }

    // MARK: - MacBook Frame

    private var macBookFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s

        // Lid (display portion) is ~85% of total height, base is ~15%
        let lidH: CGFloat = bodyH * 0.85
        let baseH: CGFloat = bodyH * 0.15

        // Screen lives in the lid, not the full body
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = lidH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        // Camera notch
        let notchW: CGFloat = 14 * s
        let notchH: CGFloat = 14 * s

        return VStack(spacing: 0) {
            // Lid
            ZStack {
                deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH, s: s)
                screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH, s: s)

                // Camera notch
                RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                    .fill(.black.opacity(0.5))
                    .frame(width: notchW, height: notchH)
                    .offset(y: -(lidH / 2 - bezelTB / 2))

                shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH)
            }

            // Base/keyboard area
            ZStack {
                UnevenRoundedRectangle(
                    topLeadingRadius: 1 * s,
                    bottomLeadingRadius: bodyCornerR * 0.5,
                    bottomTrailingRadius: bodyCornerR * 0.5,
                    topTrailingRadius: 1 * s
                )
                .fill(bodyColor)
                .frame(width: bodyW, height: baseH)
                .shadow(color: .black.opacity(0.2), radius: 2 * s, y: 1 * s)

                // Hinge line
                Rectangle()
                    .fill(.black.opacity(0.15))
                    .frame(width: bodyW * 0.98, height: 1 * s)
                    .offset(y: -(baseH / 2))

                // Trackpad
                RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5 * s)
                    .frame(width: bodyW * 0.35, height: baseH * 0.55)
                    .offset(y: 2 * s)
            }
        }
        .frame(width: bodyW, height: bodyH)
    }

    // MARK: - Android Phone Frame

    private var androidPhoneFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = bodyH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        // Punch-hole camera: small circle top-center
        let cameraD: CGFloat = 8 * s
        let cameraOffsetFromScreenTop: CGFloat = screenH * 0.022 + cameraD / 2

        // Gesture bar at bottom
        let gestureW: CGFloat = screenW * 0.30
        let gestureH: CGFloat = 2.5 * s
        let gestureOffsetFromScreenBottom: CGFloat = 6 * s + gestureH / 2

        // Button dimensions
        let btnDepth: CGFloat = category.buttonDepth * s
        let btnColor = buttonColor

        // Right side: volume up, volume down, power
        let volUpH: CGFloat = 30 * s
        let volUpY: CGFloat = bodyH * 0.32
        let volDownH: CGFloat = 30 * s
        let volDownY: CGFloat = bodyH * 0.42
        let powerH: CGFloat = 38 * s
        let powerY: CGFloat = bodyH * 0.55

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        let totalW = bodyW + btnDepth * 2

        return ZStack {
            deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)
            screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)

            // Punch-hole camera
            Circle()
                .fill(.black)
                .frame(width: cameraD, height: cameraD)
                .overlay(
                    Circle()
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5 * s)
                )
                .offset(y: -(screenH / 2 - cameraOffsetFromScreenTop))

            // Gesture bar
            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: gestureW, height: gestureH)
                .offset(y: screenH / 2 - gestureOffsetFromScreenBottom)

            // Right side buttons (volume up, volume down, power)
            sideButton(width: btnDepth, height: volUpH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - volUpY))
            sideButton(width: btnDepth, height: volDownH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - volDownY))
            sideButton(width: btnDepth, height: powerH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - powerY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: totalW, height: bodyH)
    }

    // MARK: - Android Tablet Frame

    private var androidTabletFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = bodyH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        // Front camera: small dot centered on top edge
        let cameraD: CGFloat = 6 * s
        let cameraOffsetFromTop: CGFloat = bezelTB / 2

        // Gesture bar at bottom
        let gestureW: CGFloat = screenW * 0.25
        let gestureH: CGFloat = 2.5 * s
        let gestureOffsetFromScreenBottom: CGFloat = 6 * s + gestureH / 2

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        return ZStack {
            deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)
            screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)

            // Front camera (dot at top center)
            Circle()
                .fill(.black.opacity(0.35))
                .frame(width: cameraD, height: cameraD)
                .offset(y: -(bodyH / 2 - cameraOffsetFromTop))

            // Gesture bar
            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: gestureW, height: gestureH)
                .offset(y: screenH / 2 - gestureOffsetFromScreenBottom)

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: bodyW, height: bodyH)
    }

    // MARK: - Shared Helpers

    private func deviceBody(bodyShape: RoundedRectangle, bodyW: CGFloat, bodyH: CGFloat, s: CGFloat) -> some View {
        ZStack {
            bodyShape
                .fill(bodyColor)
                .frame(width: bodyW, height: bodyH)
                .shadow(color: .black.opacity(0.25), radius: 4 * s, y: 2 * s)

            bodyShape
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.12), .white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5 * s
                )
                .frame(width: bodyW, height: bodyH)
        }
    }

    @ViewBuilder
    private func screenArea(screenShape: RoundedRectangle, screenW: CGFloat, screenH: CGFloat, bodyShape: RoundedRectangle, bodyW: CGFloat, bodyH: CGFloat, s: CGFloat) -> some View {
        Group {
            if let screenshotImage {
                Image(nsImage: screenshotImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Color.white
            }
        }
        .frame(width: screenW, height: screenH)
        .clipShape(screenShape)
        .mask {
            bodyShape
                .frame(width: bodyW, height: bodyH)
        }
        .overlay {
            screenShape
                .strokeBorder(.black.opacity(0.08), lineWidth: max(0.5, 0.5 * s))
        }
    }

    private func shineOverlay(bodyShape: RoundedRectangle, bodyW: CGFloat, bodyH: CGFloat) -> some View {
        bodyShape
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.08), location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: .white.opacity(0.03), location: 1),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: bodyW, height: bodyH)
            .allowsHitTesting(false)
    }

    // MARK: - Button Helpers

    private func sideButton(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }

    private var buttonColor: Color {
        let c = bodyColor.sRGBComponents
        return Color(red: min(1.0, c.r + 0.055), green: min(1.0, c.g + 0.055), blue: min(1.0, c.b + 0.055))
    }

    private static func snapshotDeviceModel(
        frame: DeviceFrame,
        width: CGFloat,
        height: CGFloat,
        screenshotImage: NSImage?,
        pitch: Double,
        yaw: Double,
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

    fileprivate static func makeDeviceModelScene(
        frame: DeviceFrame,
        viewportSize: CGSize,
        screenshotImage: NSImage?,
        pitch: Double,
        yaw: Double,
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
        flattenBodyMaterials(in: contentNode, modelSpec: modelSpec, tintColor: bodyTintColor)
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
        ambientLight.intensity = 520
        ambientLight.color = NSColor.white
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        sceneRoot.addChildNode(ambientNode)

        let keyLight = SCNLight()
        keyLight.type = .omni
        keyLight.intensity = 1600
        keyLight.color = NSColor.white
        let keyNode = SCNNode()
        keyNode.light = keyLight
        keyNode.position = SCNVector3(-1.8, 2.4, 4.6)
        sceneRoot.addChildNode(keyNode)

        let rimLight = SCNLight()
        rimLight.type = .directional
        rimLight.intensity = 900
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

        // Calculate visible area at the model's depth (z=0) from camera FOV
        let fovRadians = camera.fieldOfView * .pi / 180
        let visibleHeight = 2 * cameraZ * tan(fovRadians / 2)
        let aspect = viewportSize.width / viewportSize.height
        let visibleWidth = visibleHeight * aspect

        let insetFactor: CGFloat = 0.9
        let availableWidth = visibleWidth * insetFactor
        let availableHeight = visibleHeight * insetFactor

        // Get the model's world-space bounding box
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

        // Re-center after scaling
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
            applyScreenReplacementMaterial(in: contentNode, modelSpec: modelSpec, screenshotImage: screenshotImage)
        }
    }

    private static func flattenBodyMaterials(
        in contentNode: SCNNode,
        modelSpec: DeviceFrameModelSpec,
        tintColor: NSColor? = nil
    ) {
        enumerateNodes(in: contentNode) { node in
            guard let geometry = node.geometry else { return }
            geometry.materials = geometry.materials.map { material in
                guard shouldFlattenBodyMaterial(material, screenMaterialName: modelSpec.screenMaterialName) else {
                    return material.copy() as? SCNMaterial ?? SCNMaterial()
                }

                let flattened = material.copy() as? SCNMaterial ?? SCNMaterial()
                flattened.name = material.name
                flattened.lightingModel = .lambert
                if let tintColor {
                    flattened.multiply.contents = tintColor
                }
                flattened.specular.contents = NSColor.black
                flattened.reflective.contents = NSColor.black
                flattened.metalness.contents = 0.0
                flattened.roughness.contents = 1.0
                flattened.shininess = 0.0
                flattened.fresnelExponent = 0.0
                flattened.locksAmbientWithDiffuse = true
                return flattened
            }
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

    private static func shouldFlattenBodyMaterial(
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

        // Remap UVs from atlas sub-region to full 0...1 range so the screenshot fills the screen.
        let remappedGeometry = remapUVsToFullRange(geometry)

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

    /// Remaps UV coordinates of a geometry so they span the full 0...1 range.
    private static func remapUVsToFullRange(_ geometry: SCNGeometry) -> SCNGeometry {
        guard let uvSource = geometry.sources.first(where: { $0.semantic == .texcoord }) else {
            return geometry
        }

        let vectorCount = uvSource.vectorCount
        let data = uvSource.data
        let stride = uvSource.dataStride
        let offset = uvSource.dataOffset

        // Single pass: read UVs, track bounds, then remap
        var rawUVs = [CGPoint]()
        rawUVs.reserveCapacity(vectorCount)
        var minU: Float = .greatestFiniteMagnitude, maxU: Float = -.greatestFiniteMagnitude
        var minV: Float = .greatestFiniteMagnitude, maxV: Float = -.greatestFiniteMagnitude
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.baseAddress!
            for i in 0..<vectorCount {
                let base = bytes + stride * i + offset
                let u = base.load(as: Float.self)
                let v = (base + 4).load(as: Float.self)
                minU = min(minU, u); maxU = max(maxU, u)
                minV = min(minV, v); maxV = max(maxV, v)
                rawUVs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }

        let rangeU = maxU - minU
        let rangeV = maxV - minV
        guard rangeU > 0.001, rangeV > 0.001 else { return geometry }

        for i in 0..<rawUVs.count {
            rawUVs[i] = CGPoint(
                x: (rawUVs[i].x - CGFloat(minU)) / CGFloat(rangeU),
                y: (rawUVs[i].y - CGFloat(minV)) / CGFloat(rangeV)
            )
        }

        let newUVSource = SCNGeometrySource(textureCoordinates: rawUVs)

        // Keep all non-texcoord sources
        let otherSources = geometry.sources.filter { $0.semantic != .texcoord }
        let newGeometry = SCNGeometry(sources: otherSources + [newUVSource], elements: geometry.elements)
        newGeometry.materials = geometry.materials
        return newGeometry
    }

    /// 90° CW rotation + horizontal flip around UV center.
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

private struct LiveDeviceModelView: NSViewRepresentable {
    let frame: DeviceFrame
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?
    let pitch: Double
    let yaw: Double
    let bodyTintColor: NSColor?

    func makeNSView(context: Context) -> SCNView {
        let scnView = RetinaSCNView(frame: NSRect(x: 0, y: 0, width: max(1, width), height: max(1, height)))
        scnView.backgroundColor = .clear
        scnView.wantsLayer = true
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
        update(nsView)
    }

    private func update(_ scnView: SCNView) {
        guard let (scene, cameraNode) = DeviceFrameView.makeDeviceModelScene(
            frame: frame,
            viewportSize: CGSize(width: max(1, width), height: max(1, height)),
            screenshotImage: screenshotImage,
            pitch: pitch,
            yaw: yaw,
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
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
    }
}
