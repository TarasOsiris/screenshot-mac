import SwiftUI

// iPhone 17 device frame with accurate physical proportions.
//
// Physical specs (mm):
//   Body: 149.6 H × 71.5 W × 7.95 D
//   Bezels: 1.44 top/bottom, 1.41 left/right
//   Display: 6.3" OLED, 2622 × 1206 px @ 460 ppi
//   Screen-to-body: ~90.1%
//   Display corner radius: 62 pts (186 px @ 3x)
//
// Base unit: 220 px width → scale factor 3.077 px/mm
// All dimensions derived from mm × 3.077

struct DeviceFrameView: View {
    let category: DeviceCategory
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    var screenshotImage: NSImage? = nil

    private var scale: CGFloat {
        let base = category.baseDimensions
        return min(width / base.width, height / base.height)
    }

    var body: some View {
        switch category {
        case .iphone:
            iPhoneFrame
        }
    }

    // MARK: - iPhone 17 Frame

    private var iPhoneFrame: some View {
        let s = scale

        // Body: 71.5 × 149.6 mm → 220 × 460
        let bodyW: CGFloat = 220 * s
        let bodyH: CGFloat = 460 * s

        // Bezels: 1.41mm L/R → 4.34, 1.44mm T/B → 4.43
        let bezelLR: CGFloat = 4.34 * s
        let bezelTB: CGFloat = 4.43 * s

        // Screen
        let screenW: CGFloat = bodyW - bezelLR * 2
        let screenH: CGFloat = bodyH - bezelTB * 2

        // Corner radii — body ~11mm → 33.8, screen 62pt@3x on 1206px display → 32.6
        let bodyCornerR: CGFloat = 34 * s
        // The screen is inset by bezels, so its effective radius must also be inset.
        // If this is too large, rendered pixels can protrude past the body corners on export.
        let maxScreenCornerR = max(0, bodyCornerR - max(bezelLR, bezelTB))
        let screenCornerR = min(33 * s, maxScreenCornerR)

        // Dynamic Island: ~126 × 37 pts @ 3x = 378 × 111 px on 1206 × 2622 display
        // Proportional to screen: 31.3% W, 4.2% H
        let diW: CGFloat = screenW * 0.313
        let diH: CGFloat = screenH * 0.042
        // Position: ~14 pts (42px) from screen top = 1.6% of screen height
        let diOffsetFromScreenTop: CGFloat = screenH * 0.016 + diH / 2

        // Home indicator: ~134 × 5 pts @ 3x = 402 × 15 px → 33.3% of screen W
        let homeW: CGFloat = screenW * 0.333
        let homeH: CGFloat = 2.5 * s
        let homeOffsetFromScreenBottom: CGFloat = 8 * s + homeH / 2

        // Button dimensions (protruding from body edge)
        let btnDepth: CGFloat = 2.5 * s

        // Left side buttons (Action + Volume Up + Volume Down)
        // Action button: ~9.5mm tall, center at ~35% from top
        let actionH: CGFloat = 29 * s
        let actionY: CGFloat = bodyH * 0.35
        // Volume Up: ~11mm tall, center at ~44% from top
        let volUpH: CGFloat = 34 * s
        let volUpY: CGFloat = bodyH * 0.44
        // Volume Down: ~11mm tall, center at ~54% from top
        let volDownH: CGFloat = 34 * s
        let volDownY: CGFloat = bodyH * 0.54

        // Right side buttons
        // Side/Power: ~15mm tall, center at ~38% from top
        let powerH: CGFloat = 46 * s
        let powerY: CGFloat = bodyH * 0.38
        // Camera Control: ~8mm, capacitive, center at ~67% from top
        let camCtrlH: CGFloat = 25 * s
        let camCtrlY: CGFloat = bodyH * 0.67

        let btnColor = buttonColor

        let bodyShape = RoundedRectangle(cornerRadius: bodyCornerR, style: .continuous)
        let screenShape = RoundedRectangle(cornerRadius: screenCornerR, style: .continuous)

        return ZStack {
            // Body
            bodyShape
                .fill(bodyColor)
                .frame(width: bodyW, height: bodyH)
                .shadow(color: .black.opacity(0.25), radius: 4 * s, y: 2 * s)

            // Subtle edge highlight
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

            // Screen area (must be hard-clipped to rounded corners)
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
            // Action button (small, round-ish)
            sideButton(width: btnDepth, height: actionH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - actionY))

            // Volume Up
            sideButton(width: btnDepth, height: volUpH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volUpY))

            // Volume Down
            sideButton(width: btnDepth, height: volDownH, color: btnColor)
                .offset(x: -(bodyW / 2 + btnDepth / 2), y: -(bodyH / 2 - volDownY))

            // Right side buttons
            // Power / Side button
            sideButton(width: btnDepth, height: powerH, color: btnColor)
                .offset(x: bodyW / 2 + btnDepth / 2, y: -(bodyH / 2 - powerY))

            // Camera Control (flush capacitive — thinner, subtler)
            sideButton(width: btnDepth * 0.7, height: camCtrlH, color: btnColor.opacity(0.7))
                .offset(x: bodyW / 2 + btnDepth * 0.35, y: -(bodyH / 2 - camCtrlY))

            // Shine overlay
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
    }

    // MARK: - Button Helpers

    private func sideButton(width: CGFloat, height: CGFloat, color: Color) -> some View {
        RoundedRectangle(cornerRadius: width / 2, style: .continuous)
            .fill(color)
            .frame(width: width, height: height)
    }

    private var buttonColor: Color {
        let nsColor = NSColor(bodyColor).usingColorSpace(.sRGB) ?? NSColor(bodyColor)
        let r = min(1.0, nsColor.redComponent + 0.055)
        let g = min(1.0, nsColor.greenComponent + 0.055)
        let b = min(1.0, nsColor.blueComponent + 0.055)
        return Color(red: r, green: g, blue: b)
    }
}
