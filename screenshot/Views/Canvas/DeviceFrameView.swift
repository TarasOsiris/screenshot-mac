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

struct DeviceFrameView: View {
    let category: DeviceCategory
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    var screenshotImage: NSImage? = nil
    /// When set, renders using a real PNG frame from the catalog instead of programmatic drawing.
    var deviceFrameId: String? = nil

    private var scale: CGFloat {
        let base = category.baseDimensions
        return min(width / base.width, height / base.height)
    }

    var body: some View {
        if let frameId = deviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            imageBasedFrame(frame: frame)
        } else {
            programmaticFrame
        }
    }

    // MARK: - Image-Based Frame

    @ViewBuilder
    private func imageBasedFrame(frame: DeviceFrame) -> some View {
        let spec = frame.spec

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
            if let frameImage = NSImage(named: frame.imageName) {
                Image(nsImage: frameImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
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

        // Dynamic Island: ~126 × 37 pts @ 3x = 378 × 111 px on 1206 × 2622 display
        let diW: CGFloat = screenW * 0.313
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
            Capsule()
                .fill(.black)
                .frame(width: diW, height: diH)
                .overlay(
                    Capsule()
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
}
