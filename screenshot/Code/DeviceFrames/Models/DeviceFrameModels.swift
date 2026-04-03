import SwiftUI

enum DeviceFrameScreenRenderingMode: Equatable {
    case replaceMaterial
    case overlayPlane
}

enum DeviceFrameFamily: String, CaseIterable, Identifiable {
    case iphone = "iPhone"
    case android = "Android"
    case ipad = "iPad"
    case mac = "Mac"
    case other = "Other"

    var id: String { rawValue }

    var genericCategories: [DeviceCategory] {
        switch self {
        case .iphone:
            [.iphone]
        case .android:
            [.androidPhone, .androidTablet]
        case .ipad:
            [.ipadPro11, .ipadPro13]
        case .mac:
            [.macbook]
        case .other:
            [.invisible]
        }
    }
}

/// Describes the screen area within a device frame PNG image.
struct DeviceFrameImageSpec {
    /// Frame PNG dimensions.
    let frameWidth: CGFloat
    let frameHeight: CGFloat

    /// Pixel insets from frame edge to screen area.
    let screenLeft: CGFloat
    let screenTop: CGFloat
    let screenRight: CGFloat
    let screenBottom: CGFloat

    /// Screen corner radius in frame image pixels.
    let screenCornerRadius: CGFloat

    /// Screen insets as fractions of frame dimensions (for scaling).
    var leftFraction: CGFloat { screenLeft / frameWidth }
    var topFraction: CGFloat { screenTop / frameHeight }
    var rightFraction: CGFloat { screenRight / frameWidth }
    var bottomFraction: CGFloat { screenBottom / frameHeight }
    var cornerRadiusFraction: CGFloat { screenCornerRadius / frameHeight }

    /// Landscape variant (swap dimensions and insets).
    var landscape: DeviceFrameImageSpec {
        DeviceFrameImageSpec(
            frameWidth: frameHeight,
            frameHeight: frameWidth,
            screenLeft: screenTop,
            screenTop: screenRight,
            screenRight: screenBottom,
            screenBottom: screenLeft,
            screenCornerRadius: screenCornerRadius
        )
    }
}

struct DeviceFrameModelSpec: Equatable {
    let resourceName: String
    let resourceExtension: String
    let resourceSubdirectory: String?
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

struct DeviceFrameCatalogEntry {
    let groupId: String
    let modelName: String
    let family: DeviceFrameFamily
    let fallbackCategory: DeviceCategory
    let colors: [String]
    let baseSpec: DeviceFrameImageSpec
    let modelSpec: DeviceFrameModelSpec?
    let landscapeOnly: Bool
    let suggestedSizePreset: String?
}

/// A single real device frame image — one entry per PNG file.
struct DeviceFrame: Identifiable, Equatable {
    let id: String
    let modelName: String
    let colorName: String
    let isLandscape: Bool
    let fallbackCategory: DeviceCategory
    let imageName: String?
    let spec: DeviceFrameImageSpec
    let modelSpec: DeviceFrameModelSpec?

    var orientationLabel: String { isLandscape ? "Landscape" : "Portrait" }
    var isModelBacked: Bool { modelSpec != nil }

    var icon: String {
        switch fallbackCategory {
        case .iphone:
            return isLandscape ? "iphone.landscape" : "iphone"
        case .ipadPro11, .ipadPro13:
            return isLandscape ? "ipad.landscape" : "ipad"
        case .macbook:
            return "laptopcomputer"
        case .androidPhone:
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

struct DeviceFrameColorGroup: Identifiable {
    let id: String
    let name: String
    let frames: [DeviceFrame]

    var swatch: Color? { DeviceFrameColorSwatches.color(named: name) }
}

struct DeviceFrameGroup: Identifiable {
    let id: String
    let name: String
    let family: DeviceFrameFamily
    let suggestedSizePreset: String?
    let colorGroups: [DeviceFrameColorGroup]

    var frames: [DeviceFrame] { colorGroups.flatMap(\.frames) }
}

struct DeviceFrameCatalogSection: Identifiable {
    let family: DeviceFrameFamily
    let categories: [DeviceCategory]
    let groups: [DeviceFrameGroup]

    var id: DeviceFrameFamily { family }
    var title: String { family.rawValue }
}

private enum DeviceFrameColorSwatches {
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
        default:
            nil
        }
    }
}