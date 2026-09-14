import SwiftUI

nonisolated enum DeviceFrameScreenRenderingMode: Equatable {
    case replaceMaterial
    case overlayPlane
}

nonisolated enum DeviceFrameFamily: String, CaseIterable, Identifiable {
    case iphone = "iPhone"
    case android = "Android"
    case ipad = "iPad"
    case mac = "Mac"
    case watch = "Watch"
    case other = "Other"

    var id: String { rawValue }

    var genericCategories: [DeviceCategory] {
        switch self {
        case .iphone:
            [.iphone]
        case .android:
            [.androidPhone, .pixel9, .androidTablet]
        case .ipad:
            [.ipadPro11, .ipadPro13]
        case .mac:
            [.macbook]
        case .watch:
            []
        case .other:
            [.invisible]
        }
    }
}

/// Describes the screen area within a device frame PNG image.
///
/// Everything here is consumed as a *fraction* (see below), so these are the resolution the insets
/// were measured at — not the shipped PNG's pixel size, which `tools/optimize-device-frames.py`
/// caps independently. Don't re-measure insets against the shipped art, and don't "correct" these
/// to match it: `DeviceFrame.baseDimensions` divides them by 6 for the default insert size of a
/// new device shape, so editing them resizes every newly inserted device.
nonisolated struct DeviceFrameImageSpec {
    /// Frame dimensions the insets below were measured against.
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    /// Pixel insets from frame edge to screen area.
    let screenLeft: CGFloat
    let screenTop: CGFloat
    let screenRight: CGFloat
    let screenBottom: CGFloat

    /// Screen corner radii in frame image pixels.
    let screenCornerRadii: RectangleCornerRadii

    /// Screen insets as fractions of frame dimensions (for scaling).
    var leftFraction: CGFloat { screenLeft / frameWidth }
    var topFraction: CGFloat { screenTop / frameHeight }
    var rightFraction: CGFloat { screenRight / frameWidth }
    var bottomFraction: CGFloat { screenBottom / frameHeight }

    /// The screen area of a frame drawn into `size`.
    func screenRect(in size: CGSize) -> CGRect {
        CGRect(
            x: size.width * leftFraction,
            y: size.height * topFraction,
            width: size.width * (1 - leftFraction - rightFraction),
            height: size.height * (1 - topFraction - bottomFraction)
        )
    }

    /// Corner radii for a screen drawn `height` tall and grown by `bleed`; a square corner stays square.
    func clipCornerRadii(height: CGFloat, bleed: CGFloat) -> RectangleCornerRadii {
        func scaled(_ radius: CGFloat) -> CGFloat {
            radius > 0 ? height * radius / frameHeight + bleed : 0
        }
        return RectangleCornerRadii(
            topLeading: scaled(screenCornerRadii.topLeading),
            bottomLeading: scaled(screenCornerRadii.bottomLeading),
            bottomTrailing: scaled(screenCornerRadii.bottomTrailing),
            topTrailing: scaled(screenCornerRadii.topTrailing)
        )
    }

    /// The spec for the art turned clockwise by `degrees`, the same turn `DeviceFrameImageView`
    /// applies to the portrait PNG — insets and corners have to follow the art, not just swap axes.
    func landscape(rotatedClockwiseBy degrees: Double) -> DeviceFrameImageSpec {
        var (left, top, right, bottom) = (screenLeft, screenTop, screenRight, screenBottom)
        var corners = screenCornerRadii
        let quarterTurns = ((Int((degrees / 90).rounded()) % 4) + 4) % 4
        for _ in 0..<quarterTurns {
            (left, top, right, bottom) = (bottom, left, top, right)
            corners = corners.rotatedClockwise
        }
        return DeviceFrameImageSpec(
            frameWidth: frameHeight,
            frameHeight: frameWidth,
            screenLeft: left,
            screenTop: top,
            screenRight: right,
            screenBottom: bottom,
            screenCornerRadii: corners
        )
    }
}

nonisolated extension DeviceFrameImageSpec {
    init(
        frameWidth: CGFloat, frameHeight: CGFloat,
        screenLeft: CGFloat, screenTop: CGFloat, screenRight: CGFloat, screenBottom: CGFloat,
        screenCornerRadius: CGFloat
    ) {
        self.init(
            frameWidth: frameWidth, frameHeight: frameHeight,
            screenLeft: screenLeft, screenTop: screenTop, screenRight: screenRight, screenBottom: screenBottom,
            screenCornerRadii: RectangleCornerRadii(uniform: screenCornerRadius)
        )
    }
}

nonisolated extension RectangleCornerRadii {
    init(uniform radius: CGFloat) {
        self.init(topLeading: radius, bottomLeading: radius, bottomTrailing: radius, topTrailing: radius)
    }

    /// Rounded top, square bottom — a laptop screen meeting its hinge.
    init(top radius: CGFloat) {
        self.init(topLeading: radius, topTrailing: radius)
    }

    var rotatedClockwise: RectangleCornerRadii {
        RectangleCornerRadii(
            topLeading: bottomLeading,
            bottomLeading: bottomTrailing,
            bottomTrailing: topTrailing,
            topTrailing: topLeading
        )
    }
}

nonisolated struct DeviceFrameModelSpec: Equatable {
    let resourceName: String
    let resourceExtension: String
    let screenMaterialName: String?
    let disabledNodeNames: Set<String>
    let screenRenderingMode: DeviceFrameScreenRenderingMode
    let targetBodyHeight: CGFloat
    let cameraDistance: CGFloat
    let baseYawDegrees: Double
    let defaultPitch: Double
    let defaultYaw: Double
    let screenUVPadding: CGFloat
    let screenUVOffsetY: CGFloat
}

nonisolated struct DeviceFrameCatalogEntry {
    let groupId: String
    let modelName: String
    let family: DeviceFrameFamily
    let fallbackCategory: DeviceCategory
    let colors: [String]
    let baseSpec: DeviceFrameImageSpec
    let modelSpec: DeviceFrameModelSpec?
    let landscapeOnly: Bool
    /// When set, the landscape frame reuses the portrait PNG rotated by this many degrees
    /// instead of shipping a second asset. Direction is per-device: the shipped iPhone/iPad
    /// landscape art was rendered counter-clockwise (270°), the Apple Watch and iPhone Duo inner
    /// screen clockwise (90°) — the Duo's outer screen is 270° like the other phones.
    var landscapeRotationDegrees: Double?
    var iconOverride: String?
    let suggestedSizePreset: String?
    /// Picker order is newest-first, so the category default is flagged rather than inferred from order.
    var isCategoryDefault = false
}

/// A single real device frame image — one entry per PNG file.
nonisolated struct DeviceFrame: Identifiable, Equatable {
    let id: String
    let modelName: String
    let colorName: String
    let isLandscape: Bool
    let fallbackCategory: DeviceCategory
    let imageName: String?
    let spec: DeviceFrameImageSpec
    let modelSpec: DeviceFrameModelSpec?
    let iconOverride: String?
    /// When set, `imageName` is the portrait PNG and the renderer must rotate it by this many
    /// degrees. `spec` already reflects the post-rotation (landscape) dimensions.
    var landscapeRotationDegrees: Double?

    var orientationLabel: String { isLandscape ? "Landscape" : "Portrait" }
    var isModelBacked: Bool { modelSpec != nil }

    var icon: String {
        if let iconOverride { return iconOverride }
        switch fallbackCategory {
        case .iphone:
            return isLandscape ? "iphone.landscape" : "iphone"
        case .ipadPro11, .ipadPro13:
            return isLandscape ? "ipad.landscape" : "ipad"
        case .macbook:
            return "laptopcomputer"
        case .androidPhone, .pixel9:
            return isLandscape ? "iphone.gen3.landscape" : "iphone.gen3"
        case .androidTablet:
            return isLandscape ? "ipad.gen2.landscape" : "ipad.gen2"
        case .invisible:
            return "rectangle.dashed"
        }
    }

    var label: String { "\(modelName) - \(colorName) - \(orientationLabel)" }
    var shortLabel: String { "\(colorName) - \(orientationLabel)" }

    var baseDimensions: (width: CGFloat, height: CGFloat) {
        (spec.frameWidth / 6, spec.frameHeight / 6)
    }

    static func == (lhs: DeviceFrame, rhs: DeviceFrame) -> Bool { lhs.id == rhs.id }
}

nonisolated struct DeviceFrameColorGroup: Identifiable {
    let id: String
    let name: String
    let frames: [DeviceFrame]

    var swatch: Color? { DeviceFrameColorSwatches.color(named: name) }
}

nonisolated struct DeviceFrameGroup: Identifiable {
    let id: String
    let name: String
    let family: DeviceFrameFamily
    let suggestedSizePreset: String?
    let colorGroups: [DeviceFrameColorGroup]

    var frames: [DeviceFrame] { colorGroups.flatMap(\.frames) }
    var prefersVariantMenu: Bool { family == .watch }
}

nonisolated struct DeviceFrameCatalogSection: Identifiable {
    let family: DeviceFrameFamily
    let categories: [DeviceCategory]
    let groups: [DeviceFrameGroup]

    var id: DeviceFrameFamily { family }
    var title: String { family.rawValue }
}

private nonisolated enum DeviceFrameColorSwatches {
    static func color(named name: String) -> Color? {
        switch name.lowercased() {
        case "black":
            Color(red: 0.13, green: 0.13, blue: 0.15)
        case "white":
            Color(red: 0.95, green: 0.96, blue: 0.97)
        case "lavender":
            Color(red: 0.72, green: 0.67, blue: 0.88)
        case "mist blue":
            Color(red: 0.66, green: 0.78, blue: 0.89)
        case "sage":
            Color(red: 0.68, green: 0.74, blue: 0.62)
        case "cosmic orange":
            Color(red: 0.78, green: 0.47, blue: 0.28)
        case "deep blue":
            Color(red: 0.24, green: 0.34, blue: 0.56)
        case "silver":
            Color(red: 0.82, green: 0.84, blue: 0.87)
        case "cloud white":
            Color(red: 0.94, green: 0.95, blue: 0.94)
        case "light gold":
            Color(red: 0.86, green: 0.79, blue: 0.64)
        case "sky blue":
            Color(red: 0.55, green: 0.75, blue: 0.93)
        case "space black":
            Color(red: 0.18, green: 0.19, blue: 0.21)
        case "midnight":
            Color(red: 0.13, green: 0.16, blue: 0.24)
        case "space gray":
            Color(red: 0.39, green: 0.42, blue: 0.45)
        case "burgundy":
            Color(red: 0.48, green: 0.22, blue: 0.26)
        case "glacier":
            Color(red: 0.78, green: 0.83, blue: 0.89)
        case "night sky":
            Color(red: 0.20, green: 0.25, blue: 0.31)
        case "star white":
            Color(red: 0.93, green: 0.93, blue: 0.91)
        default:
            nil
        }
    }
}
