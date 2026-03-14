import SwiftUI

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

// MARK: - Real Device Frame

/// A single real device frame image — one entry per PNG file.
struct DeviceFrame: Identifiable, Equatable {
    let id: String              // Persistence key: "iphone17-black-portrait"
    let modelName: String       // "iPhone 17"
    let colorName: String       // "Black"
    let isLandscape: Bool
    let fallbackCategory: DeviceCategory
    let imageName: String       // Asset catalog name: "DeviceFrames/iphone17-black-portrait"
    let spec: DeviceFrameImageSpec

    var orientationLabel: String { isLandscape ? "Landscape" : "Portrait" }

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

    /// All available real device frames, grouped by model.
    static let groups: [DeviceFrameGroup] = buildGroups()

    /// Flat list of all frames.
    static let allFrames: [DeviceFrame] = groups.flatMap(\.frames)

    /// O(1) lookup by persistence ID.
    private static let framesByID: [String: DeviceFrame] = Dictionary(uniqueKeysWithValues: allFrames.map { ($0.id, $0) })

    /// Look up a frame by its persistence ID.
    static func frame(for id: String) -> DeviceFrame? {
        framesByID[id]
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
        landscapeOnly: Bool = false
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
                    imageName: "DeviceFrames/\(frameId)",
                    spec: isLandscape ? landscapeSpec : baseSpec
                )
            }
            return DeviceFrameColorGroup(id: "\(id)-\(slug)", name: color, frames: frames)
        }
        return DeviceFrameGroup(id: id, name: name, colorGroups: colorGroups)
    }
}
