import SwiftUI

enum DeviceFrameScreenRenderingMode: Equatable {
    case replaceMaterial
    case overlayPlane
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
            frameWidth: frameHeight, frameHeight: frameWidth,
            screenLeft: screenTop, screenTop: screenRight,
            screenRight: screenBottom, screenBottom: screenLeft,
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
    /// Extra UV padding so the screenshot doesn't extend behind the bezel.
    /// A value of 0.03 means ~3 % of the screen texture is reserved for the
    /// hidden area on each side.  With `.clamp` wrapping the edge pixels
    /// stretch into the padding zone, keeping actual content fully visible.
    let screenUVPadding: CGFloat
}

// MARK: - Real Device Frame

/// A single real device frame image — one entry per PNG file.
struct DeviceFrame: Identifiable, Equatable {
    let id: String              // Persistence key: "iphone17-black-portrait"
    let modelName: String       // "iPhone 17"
    let colorName: String       // "Black"
    let isLandscape: Bool
    let fallbackCategory: DeviceCategory
    let imageName: String?      // Asset catalog name: "DeviceFrames/iphone17-black-portrait"
    let spec: DeviceFrameImageSpec
    let modelSpec: DeviceFrameModelSpec?

    var orientationLabel: String { isLandscape ? "Landscape" : "Portrait" }
    var isModelBacked: Bool { modelSpec != nil }

    /// SF Symbol icon name based on device type and orientation.
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
        }
    }
    var label: String { "\(modelName) - \(colorName) - \(orientationLabel)" }
    var shortLabel: String { "\(colorName) - \(orientationLabel)" }

    /// Base dimensions for aspect ratio (scaled down by /6 for manageable numbers).
    var baseDimensions: (width: CGFloat, height: CGFloat) {
        (spec.frameWidth / 6, spec.frameHeight / 6)
    }

    static func == (lhs: DeviceFrame, rhs: DeviceFrame) -> Bool { lhs.id == rhs.id }
}

/// A group of real frames for one device model (e.g. "iPhone 17 Pro").
struct DeviceFrameColorGroup: Identifiable {
    let id: String        // "iphone17pro-deepblue"
    let name: String      // "Deep Blue"
    let frames: [DeviceFrame]

    var swatch: Color? { DeviceFrameColorSwatches.color(named: name) }
}

/// A group of real frames for one device model (e.g. "iPhone 17 Pro").
struct DeviceFrameGroup: Identifiable {
    let id: String        // "iphone17pro"
    let name: String      // "iPhone 17 Pro"
    let colorGroups: [DeviceFrameColorGroup]

    var frames: [DeviceFrame] { colorGroups.flatMap(\.frames) }
}

// MARK: - Catalog

struct DeviceFrameCatalog {
    // Portrait specs measured from actual PNG files.
    private static let iphone17Spec = DeviceFrameImageSpec(
        frameWidth: 1350, frameHeight: 2760,
        screenLeft: 72, screenTop: 69, screenRight: 72, screenBottom: 69,
        screenCornerRadius: 165
    )
    private static let iphone17ProMaxSpec = DeviceFrameImageSpec(
        frameWidth: 1470, frameHeight: 3000,
        screenLeft: 75, screenTop: 66, screenRight: 75, screenBottom: 66,
        screenCornerRadius: 170
    )
    private static let iphoneAirSpec = DeviceFrameImageSpec(
        frameWidth: 1380, frameHeight: 2880,
        screenLeft: 60, screenTop: 72, screenRight: 60, screenBottom: 72,
        screenCornerRadius: 165
    )
    private static let macbookAir13Spec = DeviceFrameImageSpec(
        frameWidth: 3220, frameHeight: 2100,
        screenLeft: 330, screenTop: 218, screenRight: 330, screenBottom: 218,
        screenCornerRadius: 34
    )
    private static let macbookPro14Spec = DeviceFrameImageSpec(
        frameWidth: 3944, frameHeight: 2564,
        screenLeft: 460, screenTop: 300, screenRight: 460, screenBottom: 300,
        screenCornerRadius: 40
    )
    private static let macbookPro16Spec = DeviceFrameImageSpec(
        frameWidth: 4340, frameHeight: 2860,
        screenLeft: 442, screenTop: 313, screenRight: 442, screenBottom: 313,
        screenCornerRadius: 38
    )
    private static let imac24Spec = DeviceFrameImageSpec(
        frameWidth: 4760, frameHeight: 4040,
        screenLeft: 140, screenTop: 160, screenRight: 140, screenBottom: 1360,
        screenCornerRadius: 0
    )
    private static let ipadPro11Spec = DeviceFrameImageSpec(
        frameWidth: 1880, frameHeight: 2640,
        screenLeft: 106, screenTop: 110, screenRight: 106, screenBottom: 110,
        screenCornerRadius: 55
    )
    private static let ipadPro13Spec = DeviceFrameImageSpec(
        frameWidth: 2300, frameHeight: 3000,
        screenLeft: 118, screenTop: 124, screenRight: 118, screenBottom: 124,
        screenCornerRadius: 54
    )
    private static let iphone16ModelSpec = DeviceFrameImageSpec(
        frameWidth: 148.05, frameHeight: 300.0,
        screenLeft: 7.6025, screenTop: 6.653, screenRight: 7.6025, screenBottom: 6.653,
        screenCornerRadius: 18
    )
    private static let iphone16USDZModel = DeviceFrameModelSpec(
        resourceName: "Iphone_17_pro",
        resourceExtension: "usdz",
        resourceSubdirectory: "DeviceModels",
        screenMaterialName: "Screen_BG",
        disabledNodeNames: [],
        screenRenderingMode: .replaceMaterial,
        targetBodyHeight: 2.05,
        cameraDistance: 5.4,
        baseYawDegrees: 0,
        defaultPitch: 0,
        defaultYaw: 0,
        screenUVPadding: 0.03
    )

    /// All available real device frames, grouped by model.
    static let groups: [DeviceFrameGroup] = buildGroups()

    /// Flat list of all frames.
    static let allFrames: [DeviceFrame] = groups.flatMap(\.frames)

    /// O(1) lookup by persistence ID.
    private static let framesByID: [String: DeviceFrame] = Dictionary(uniqueKeysWithValues: allFrames.map { ($0.id, $0) })

    /// O(1) reverse lookup: frame ID → group ID.
    private static let groupIdByFrameId: [String: String] = {
        var map: [String: String] = [:]
        for group in groups {
            for frame in group.frames {
                map[frame.id] = group.id
            }
        }
        return map
    }()

    /// O(1) lookup: group ID → group.
    private static let groupsByID: [String: DeviceFrameGroup] = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })

    /// O(1) lookup: category → first portrait frame ID.
    private static let firstPortraitFrameByCategory: [DeviceCategory: String] = {
        var map: [DeviceCategory: String] = [:]
        for frame in allFrames where !frame.isLandscape {
            if map[frame.fallbackCategory] == nil {
                map[frame.fallbackCategory] = frame.id
            }
        }
        return map
    }()

    /// Look up a frame by its persistence ID.
    static func frame(for id: String) -> DeviceFrame? {
        framesByID[id]
    }

    /// First portrait frame ID for a device category.
    static func firstPortraitFrameId(for category: DeviceCategory) -> String? {
        firstPortraitFrameByCategory[category]
    }

    /// Look up the device model group for a frame ID.
    static func group(forFrameId frameId: String) -> DeviceFrameGroup? {
        groupIdByFrameId[frameId].flatMap { groupsByID[$0] }
    }

    /// Look up the color group for a frame ID.
    static func colorGroup(forFrameId frameId: String) -> DeviceFrameColorGroup? {
        group(forFrameId: frameId)?.colorGroups.first { colorGroup in
            colorGroup.frames.contains { $0.id == frameId }
        }
    }

    /// Preferred frame for a device model group, preserving the current orientation/color when possible.
    static func preferredFrame(forGroupId groupId: String, matching currentFrameId: String? = nil) -> DeviceFrame? {
        guard let group = groupsByID[groupId] else { return nil }
        let currentFrame = currentFrameId.flatMap { frame(for: $0) }
        return preferredFrame(in: group, matching: currentFrame)
    }

    /// Resolve a sibling variant for the current frame with a different color and/or orientation.
    static func variant(
        forFrameId frameId: String,
        colorGroupId: String? = nil,
        isLandscape: Bool? = nil
    ) -> DeviceFrame? {
        guard let frame = frame(for: frameId),
              let group = group(forFrameId: frameId) else { return nil }

        let targetColorGroup = colorGroupId.flatMap { id in
            group.colorGroups.first { $0.id == id }
        } ?? colorGroup(forFrameId: frameId) ?? group.colorGroups.first

        guard let targetColorGroup else { return nil }
        let targetLandscape = isLandscape ?? frame.isLandscape
        return targetColorGroup.frames.first(where: { $0.isLandscape == targetLandscape }) ?? targetColorGroup.frames.first
    }

    /// Return the same frame in the opposite orientation, if it exists.
    static func toggledOrientation(for id: String) -> DeviceFrame? {
        guard let frame = frame(for: id) else { return nil }
        return variant(forFrameId: id, isLandscape: !frame.isLandscape)
    }

    /// Suggested screenshot size preset for a specific device frame.
    static func suggestedSizePreset(forFrameId frameId: String) -> String? {
        guard let frame = framesByID[frameId] else { return nil }
        let groupId = groupIdByFrameId[frameId]
        let isLandscape = frame.isLandscape
        let preset: String? = switch groupId {
        case "iphone17", "iphone17pro": "1206x2622"
        case "iphone17promax": "1320x2868"
        case "iphoneair": "1260x2736"
        case "ipadpro11": "1668x2420"
        case "ipadpro13": "2064x2752"
        case "macbookair13": "2560x1600"
        case "macbookair15", "macbookpro14": "2880x1800"
        case "macbookpro16", "imac24": "2880x1800"
        default: nil
        }
        guard let preset else { return nil }
        if isLandscape, let parsed = parseSizeString(preset), parsed.width < parsed.height {
            return "\(Int(parsed.height))x\(Int(parsed.width))"
        }
        return preset
    }

    private static func preferredFrame(in group: DeviceFrameGroup, matching currentFrame: DeviceFrame?) -> DeviceFrame? {
        let preferredColorName = currentFrame?.colorName
        let preferredOrientation = currentFrame?.isLandscape ?? false

        let preferredColorGroup = group.colorGroups.first(where: { $0.name == preferredColorName }) ?? group.colorGroups.first
        return preferredColorGroup?.frames.first(where: { $0.isLandscape == preferredOrientation })
            ?? preferredColorGroup?.frames.first(where: { !$0.isLandscape })
            ?? preferredColorGroup?.frames.first
    }

    // MARK: - Build

    private static func buildGroups() -> [DeviceFrameGroup] {
        [
            buildGroup(
                id: "iphone17", name: "iPhone 17",
                colors: ["Black", "Lavender", "Mist Blue", "Sage", "White"],
                baseSpec: iphone17Spec
            ),
            buildGroup(
                id: "iphone17pro", name: "iPhone 17 Pro",
                colors: ["Cosmic Orange", "Deep Blue", "Silver"],
                baseSpec: iphone17Spec  // Same frame dimensions as iPhone 17
            ),
            buildGroup(
                id: "iphone17promax", name: "iPhone 17 Pro Max",
                colors: ["Cosmic Orange", "Deep Blue", "Silver"],
                baseSpec: iphone17ProMaxSpec
            ),
            buildGroup(
                id: "iphoneair", name: "iPhone Air",
                colors: ["Cloud White", "Light Gold", "Sky Blue", "Space Black"],
                baseSpec: iphoneAirSpec
            ),
            buildGroup(
                id: "iphone16model", name: "iPhone 17 (3D)",
                colors: ["Default"],
                baseSpec: iphone16ModelSpec,
                modelSpec: iphone16USDZModel
            ),
            buildGroup(
                id: "ipadpro11", name: "iPad Pro 11\"",
                colors: ["Silver", "Space Gray"],
                baseSpec: ipadPro11Spec,
                fallbackCategory: .ipadPro11
            ),
            buildGroup(
                id: "ipadpro13", name: "iPad Pro 13\"",
                colors: ["Silver", "Space Gray"],
                baseSpec: ipadPro13Spec,
                fallbackCategory: .ipadPro13
            ),
            buildGroup(
                id: "macbookair13", name: "MacBook Air 13\"",
                colors: ["Midnight"],
                baseSpec: macbookAir13Spec,
                fallbackCategory: .macbook,
                landscapeOnly: true
            ),
            buildGroup(
                id: "macbookpro14", name: "MacBook Pro 14\"",
                colors: ["Silver"],
                baseSpec: macbookPro14Spec,
                fallbackCategory: .macbook,
                landscapeOnly: true
            ),
            buildGroup(
                id: "macbookpro16", name: "MacBook Pro 16\"",
                colors: ["Silver"],
                baseSpec: macbookPro16Spec,
                fallbackCategory: .macbook,
                landscapeOnly: true
            ),
            buildGroup(
                id: "imac24", name: "iMac 24\"",
                colors: ["Silver"],
                baseSpec: imac24Spec,
                fallbackCategory: .macbook,
                landscapeOnly: true
            ),
        ]
    }

    private static func buildGroup(
        id: String,
        name: String,
        colors: [String],
        baseSpec: DeviceFrameImageSpec,
        fallbackCategory: DeviceCategory = .iphone,
        landscapeOnly: Bool = false,
        modelSpec: DeviceFrameModelSpec? = nil
    ) -> DeviceFrameGroup {
        let landscapeSpec = landscapeOnly ? baseSpec : baseSpec.landscape
        let orientations: [Bool] = landscapeOnly ? [true] : [false, true]
        let colorGroups = colors.map { color -> DeviceFrameColorGroup in
            let slug = color.lowercased().replacingOccurrences(of: " ", with: "")
            let frames = orientations.map { isLandscape -> DeviceFrame in
                let orient = isLandscape ? "landscape" : "portrait"
                let frameId = "\(id)-\(slug)-\(orient)"
                return DeviceFrame(
                    id: frameId,
                    modelName: name,
                    colorName: color,
                    isLandscape: isLandscape,
                    fallbackCategory: fallbackCategory,
                    imageName: modelSpec == nil ? "DeviceFrames/\(frameId)" : nil,
                    spec: isLandscape ? landscapeSpec : baseSpec,
                    modelSpec: modelSpec
                )
            }
            return DeviceFrameColorGroup(id: "\(id)-\(slug)", name: color, frames: frames)
        }
        return DeviceFrameGroup(id: id, name: name, colorGroups: colorGroups)
    }
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
