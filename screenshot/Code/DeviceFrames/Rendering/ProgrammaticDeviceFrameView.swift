import AppKit
import SwiftUI

struct ProgrammaticDeviceFrameView: View {
    let category: DeviceCategory
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?
    let invisibleCornerRadius: CGFloat
    let invisibleOutlineWidth: CGFloat
    let invisibleOutlineColor: Color

    private var scale: CGFloat {
        let base = category.baseDimensions
        return min(width / base.width, height / base.height)
    }

    var body: some View {
        switch category {
        case .iphone:
            iPhoneFrame
        case .ipadPro11, .ipadPro13:
            iPadFrame
        case .macbook:
            macBookFrame
        case .androidPhone:
            androidPhoneFrame
        case .pixel9:
            pixel9Frame
        case .androidTablet:
            androidTabletFrame
        case .invisible:
            invisibleFrame
        }
    }

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

        let diW: CGFloat = screenW * 0.312
        let diH: CGFloat = screenH * 0.042
        let diOffsetFromScreenTop: CGFloat = screenH * 0.016 + diH / 2

        let homeW: CGFloat = screenW * 0.333
        let homeH: CGFloat = 2.5 * s
        let homeOffsetFromScreenBottom: CGFloat = 8 * s + homeH / 2

        let btnDepth: CGFloat = category.buttonDepth * s
        let btnColor = buttonColor

        let actionH: CGFloat = 29 * s
        let actionY: CGFloat = bodyH * 0.35
        let volUpH: CGFloat = 34 * s
        let volUpY: CGFloat = bodyH * 0.44
        let volDownH: CGFloat = 34 * s
        let volDownY: CGFloat = bodyH * 0.54

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

            RoundedRectangle(cornerRadius: diH / 2, style: .continuous)
                .fill(.black)
                .frame(width: diW, height: diH)
                .overlay(
                    RoundedRectangle(cornerRadius: diH / 2, style: .continuous)
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5 * s)
                )
                .offset(y: -(screenH / 2 - diOffsetFromScreenTop))

            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: homeW, height: homeH)
                .offset(y: screenH / 2 - homeOffsetFromScreenBottom)

            sideButton(width: btnDepth, height: actionH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - actionY))
            sideButton(width: btnDepth, height: volUpH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volUpY))
            sideButton(width: btnDepth, height: volDownH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volDownY))

            sideButton(width: btnDepth, height: powerH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - powerY))
            sideButton(width: btnDepth * 0.7, height: camCtrlH, color: btnColor.opacity(0.7))
                .offset(x: bodyW / 2 + btnDepth * 0.35, y: -(bodyH / 2 - camCtrlY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: totalW, height: bodyH)
    }

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

        let cameraD: CGFloat = 6 * s
        let cameraOffsetFromTop: CGFloat = bezelTB / 2

        let powerW: CGFloat = 34 * s
        let powerH: CGFloat = 2.5 * s
        let powerOffsetX: CGFloat = bodyW * 0.35

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

            Circle()
                .fill(.black.opacity(0.35))
                .frame(width: cameraD, height: cameraD)
                .offset(y: -(bodyH / 2 - cameraOffsetFromTop))

            sideButton(width: powerW, height: powerH, color: btnColor)
                .offset(x: powerOffsetX, y: -(bodyH / 2 + powerH / 2))

            sideButton(width: volBtnW, height: volUpH, color: btnColor)
                .offset(x: bodyW / 2 + volBtnW / 2, y: -(bodyH / 2 - volUpY))
            sideButton(width: volBtnW, height: volDownH, color: btnColor)
                .offset(x: bodyW / 2 + volBtnW / 2, y: -(bodyH / 2 - volDownY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: bodyW, height: bodyH)
    }

    private var macBookFrame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let bezels = category.bezels
        let bezelLR: CGFloat = bezels.lr * s
        let bezelTB: CGFloat = bezels.tb * s

        let lidH: CGFloat = bodyH * 0.85
        let baseH: CGFloat = bodyH * 0.15

        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = lidH - bezelTB * 2

        let bodyCornerR: CGFloat = category.bodyCornerRadius * s
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(category.screenCornerRadius * s, maxScreenCornerR)

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        let notchW: CGFloat = 14 * s
        let notchH: CGFloat = 14 * s

        return VStack(spacing: 0) {
            ZStack {
                deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH, s: s)
                screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH, s: s)

                RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                    .fill(.black.opacity(0.5))
                    .frame(width: notchW, height: notchH)
                    .offset(y: -(lidH / 2 - bezelTB / 2))

                shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: lidH)
            }

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

                Rectangle()
                    .fill(.black.opacity(0.15))
                    .frame(width: bodyW * 0.98, height: 1 * s)
                    .offset(y: -(baseH / 2))

                RoundedRectangle(cornerRadius: 4 * s, style: .continuous)
                    .strokeBorder(.black.opacity(0.08), lineWidth: 0.5 * s)
                    .frame(width: bodyW * 0.35, height: baseH * 0.55)
                    .offset(y: 2 * s)
            }
        }
        .frame(width: bodyW, height: bodyH)
    }

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

        let cameraD: CGFloat = 8 * s
        let cameraOffsetFromScreenTop: CGFloat = screenH * 0.022 + cameraD / 2

        let gestureW: CGFloat = screenW * 0.30
        let gestureH: CGFloat = 2.5 * s
        let gestureOffsetFromScreenBottom: CGFloat = 6 * s + gestureH / 2

        let btnDepth: CGFloat = category.buttonDepth * s
        let btnColor = buttonColor

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

            Circle()
                .fill(.black)
                .frame(width: cameraD, height: cameraD)
                .overlay(
                    Circle()
                        .strokeBorder(.black.opacity(0.06), lineWidth: 0.5 * s)
                )
                .offset(y: -(screenH / 2 - cameraOffsetFromScreenTop))

            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: gestureW, height: gestureH)
                .offset(y: screenH / 2 - gestureOffsetFromScreenBottom)

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

    private var pixel9Frame: some View {
        let s = scale
        let dims = category.bodyDimensions
        let bodyW: CGFloat = dims.width * s
        let bodyH: CGFloat = dims.height * s

        let outerRimW: CGFloat = bodyW * (7.0 / 452.0)
        let innerRimW: CGFloat = bodyW * (13.0 / 452.0)
        let totalBezel: CGFloat = outerRimW + innerRimW
        let screenW: CGFloat = bodyW - totalBezel * 2
        let screenH: CGFloat = bodyH - totalBezel * 2

        let bodyCornerR: CGFloat = bodyW * (76.0 / 452.0)
        let midCornerR: CGFloat = bodyW * (70.0 / 452.0)
        let screenCornerR: CGFloat = bodyW * (57.0 / 452.0)

        let cameraR: CGFloat = bodyW * (15.0 / 452.0)
        let cameraCenterY: CGFloat = bodyH * (54.0 / 964.0)

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let midShape = RoundedRectangle(cornerRadius: midCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        let innerRimColor = Color(red: 0.141, green: 0.125, blue: 0.125)

        return ZStack {
            bodyShape
                .fill(bodyColor)
                .frame(width: bodyW, height: bodyH)
                .shadow(color: .black.opacity(0.25), radius: 4 * s, y: 2 * s)

            midShape
                .fill(innerRimColor)
                .frame(width: bodyW - outerRimW * 2, height: bodyH - outerRimW * 2)

            screenArea(
                screenShape: screenShape,
                screenW: screenW,
                screenH: screenH,
                bodyShape: bodyShape,
                bodyW: bodyW,
                bodyH: bodyH,
                s: s
            )

            Circle()
                .fill(.black)
                .frame(width: cameraR * 2, height: cameraR * 2)
                .offset(y: -(bodyH / 2 - cameraCenterY))

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: bodyW, height: bodyH)
    }

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

        let cameraD: CGFloat = 6 * s
        let cameraOffsetFromTop: CGFloat = bezelTB / 2

        let gestureW: CGFloat = screenW * 0.25
        let gestureH: CGFloat = 2.5 * s
        let gestureOffsetFromScreenBottom: CGFloat = 6 * s + gestureH / 2

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        return ZStack {
            deviceBody(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)
            screenArea(screenShape: screenShape, screenW: screenW, screenH: screenH, bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH, s: s)

            Circle()
                .fill(.black.opacity(0.35))
                .frame(width: cameraD, height: cameraD)
                .offset(y: -(bodyH / 2 - cameraOffsetFromTop))

            Capsule()
                .fill(.black.opacity(0.15))
                .frame(width: gestureW, height: gestureH)
                .offset(y: screenH / 2 - gestureOffsetFromScreenBottom)

            shineOverlay(bodyShape: bodyShape, bodyW: bodyW, bodyH: bodyH)
        }
        .frame(width: bodyW, height: bodyH)
    }

    private var invisibleFrame: some View {
        let cornerRadius = invisibleCornerRadius
        let outlineW = invisibleOutlineWidth
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return ZStack {
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
            .frame(width: max(0, width - outlineW), height: max(0, height - outlineW))
            .clipShape(RoundedRectangle(
                cornerRadius: max(0, cornerRadius - outlineW / 2),
                style: .continuous
            ))

            if outlineW > 0 {
                shape
                    .strokeBorder(invisibleOutlineColor, lineWidth: outlineW)
                    .frame(width: width, height: height)
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }

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
    private func screenArea(
        screenShape: RoundedRectangle,
        screenW: CGFloat,
        screenH: CGFloat,
        bodyShape: RoundedRectangle,
        bodyW: CGFloat,
        bodyH: CGFloat,
        s: CGFloat
    ) -> some View {
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

    private func sideButton(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: min(width, height) / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }

    private var buttonColor: Color {
        let c = bodyColor.sRGBComponents
        return Color(
            red: min(1.0, c.r + 0.055),
            green: min(1.0, c.g + 0.055),
            blue: min(1.0, c.b + 0.055)
        )
    }
}
