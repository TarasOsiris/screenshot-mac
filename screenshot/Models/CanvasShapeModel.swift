import Foundation
import SwiftUI

enum ShapeType: String, Codable, CaseIterable {
    case rectangle
    case circle
    case star
    case text
    case image
    case device
    case svg

    var icon: String {
        switch self {
        case .rectangle: "rectangle.fill"
        case .circle: "circle.fill"
        case .star: "star.fill"
        case .text: "textformat"
        case .image: "photo"
        case .device: "iphone"
        case .svg: "chevron.left.forwardslash.chevron.right"
        }
    }

    var label: String {
        switch self {
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .star: "Star"
        case .text: "Text"
        case .image: "Image"
        case .device: "Device"
        case .svg: "SVG"
        }
    }

    /// Shape types grouped under the "Shapes" menu in the toolbar.
    static let shapeMenuTypes: [ShapeType] = [.rectangle, .circle, .star]

    var supportsOutline: Bool {
        switch self {
        case .rectangle, .circle, .star: true
        case .text, .image, .device, .svg: false
        }
    }
}

enum DeviceCategory: String, Codable, CaseIterable {
    case iphone
    case ipadPro11
    case ipadPro13
    case macbook
    case androidPhone = "android"
    case androidTablet

    var label: String {
        switch self {
        case .iphone: "iPhone"
        case .ipadPro11: "iPad Pro 11\""
        case .ipadPro13: "iPad Pro 13\""
        case .macbook: "MacBook"
        case .androidPhone: "Android Phone"
        case .androidTablet: "Android Tablet"
        }
    }

    var icon: String {
        switch self {
        case .iphone: "iphone"
        case .ipadPro11, .ipadPro13: "ipad"
        case .macbook: "laptopcomputer"
        case .androidPhone: "iphone.gen3"
        case .androidTablet: "ipad.gen2"
        }
    }

    /// Body dimensions (without side buttons).
    /// iPhone 17: 71.5 x 149.6 mm at scale 3.077 px/mm → 220 x 460.
    /// iPad Pro 11": 177.5 x 249.7 mm → 546 x 768.
    /// iPad Pro 13": 215.5 x 281.6 mm → 663 x 867.
    /// MacBook: generic 16:10 landscape proportion.
    /// Android Phone: generic modern phone ~72 x 153 mm → 221 x 470.
    /// Android Tablet: generic tablet ~165 x 254 mm → 508 x 782.
    var bodyDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .iphone: (220, 460)
        case .ipadPro11: (546, 768)
        case .ipadPro13: (663, 867)
        case .macbook: (640, 420)
        case .androidPhone: (221, 470)
        case .androidTablet: (508, 782)
        }
    }

    /// Depth of side buttons protruding from body edge.
    /// iPads and MacBooks have flush buttons (no protrusion).
    var buttonDepth: CGFloat {
        switch self {
        case .iphone, .androidPhone: 2.5
        case .ipadPro11, .ipadPro13, .macbook, .androidTablet: 0
        }
    }

    /// Bezel dimensions in base units (px at 3.077 px/mm scale).
    var bezels: (lr: CGFloat, tb: CGFloat) {
        switch self {
        case .iphone: (4.34, 4.43)
        case .ipadPro11: (26.5, 25.8)
        case .ipadPro13: (27.0, 26.0)
        case .macbook: (40, 40)
        case .androidPhone: (4.0, 4.0)
        case .androidTablet: (18.0, 18.0)
        }
    }

    /// Body corner radius in base units.
    var bodyCornerRadius: CGFloat {
        switch self {
        case .iphone: 34
        case .ipadPro11, .ipadPro13: 55
        case .macbook: 20
        case .androidPhone: 30
        case .androidTablet: 40
        }
    }

    /// Screen corner radius in base units.
    var screenCornerRadius: CGFloat {
        switch self {
        case .iphone: 33
        case .ipadPro11, .ipadPro13: 11
        case .macbook: 10
        case .androidPhone: 28
        case .androidTablet: 20
        }
    }

    /// Total bounding box including side buttons.
    var baseDimensions: (width: CGFloat, height: CGFloat) {
        let body = bodyDimensions
        return (body.width + buttonDepth * 2, body.height)
    }
}

enum TextAlign: String, Codable {
    case left
    case center
    case right
}

extension Optional where Wrapped == TextAlign {
    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        default: .center
        }
    }
}

struct CanvasShapeModel: Identifiable, Codable {
    static let deviceMinSize: CGFloat = 200
    static let defaultDeviceBodyColor = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let defaultStarPointCount = 5
    static let defaultOutlineColor: Color = .black
    static let defaultOutlineWidth: CGFloat = 4

    var id: UUID
    var type: ShapeType
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotation: Double
    var borderRadius: CGFloat
    var colorData: CodableColor
    var opacity: Double

    // Text properties
    var text: String?
    var fontName: String?
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?
    var italic: Bool?
    var uppercase: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?

    // Image properties
    var imageFileName: String?

    // Device properties
    var deviceCategory: DeviceCategory?
    var deviceBodyColorData: CodableColor?
    var deviceFrameId: String?
    var screenshotFileName: String?

    // SVG properties
    var svgContent: String?
    var svgUseColor: Bool?

    // Outline properties
    var outlineColorData: CodableColor?
    var outlineWidth: CGFloat?

    // Star properties
    var starPointCount: Int?

    // Clipping
    var clipToTemplate: Bool?

    init(
        id: UUID = UUID(),
        type: ShapeType,
        x: CGFloat = 0,
        y: CGFloat = 0,
        width: CGFloat = 200,
        height: CGFloat = 200,
        rotation: Double = 0,
        borderRadius: CGFloat = 0,
        color: Color = .white,
        opacity: Double = 1.0,
        text: String? = nil,
        fontName: String? = nil,
        fontSize: CGFloat? = nil,
        fontWeight: Int? = nil,
        textAlign: TextAlign? = nil,
        italic: Bool? = nil,
        uppercase: Bool? = nil,
        letterSpacing: CGFloat? = nil,
        lineSpacing: CGFloat? = nil,
        imageFileName: String? = nil,
        deviceCategory: DeviceCategory? = nil,
        deviceBodyColor: Color? = nil,
        deviceFrameId: String? = nil,
        screenshotFileName: String? = nil,
        svgContent: String? = nil,
        svgUseColor: Bool? = nil,
        outlineColor: Color? = nil,
        outlineWidth: CGFloat? = nil,
        starPointCount: Int? = nil,
        clipToTemplate: Bool? = nil
    ) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.rotation = rotation
        self.borderRadius = borderRadius
        self.colorData = CodableColor(color)
        self.opacity = opacity
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textAlign = textAlign
        self.italic = italic
        self.uppercase = uppercase
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.imageFileName = imageFileName
        self.deviceCategory = deviceCategory
        self.deviceBodyColorData = deviceBodyColor.map { CodableColor($0) }
        self.deviceFrameId = deviceFrameId
        self.screenshotFileName = screenshotFileName
        self.svgContent = svgContent
        self.svgUseColor = svgUseColor
        self.outlineColorData = outlineColor.map { CodableColor($0) }
        self.outlineWidth = outlineWidth
        self.starPointCount = starPointCount
        self.clipToTemplate = clipToTemplate
    }

    /// Used as a fallback when a Binding's get is called after the shape has been removed.
    static let placeholder = CanvasShapeModel(type: .rectangle)

    var color: Color {
        get { colorData.color }
        set { colorData = CodableColor(newValue) }
    }

    var outlineColor: Color? {
        get { outlineColorData?.color }
        set { outlineColorData = newValue.map { CodableColor($0) } }
    }

    /// The filename for the shape's display image (device screenshot or standalone image).
    var displayImageFileName: String? {
        get { type == .image ? imageFileName : screenshotFileName }
        set {
            if type == .image {
                imageFileName = newValue
            } else {
                screenshotFileName = newValue
            }
        }
    }

    /// All image filenames associated with this shape (for cleanup).
    var allImageFileNames: [String] {
        [screenshotFileName, imageFileName].compactMap { $0 }
    }

    /// Axis-aligned bounding box accounting for rotation.
    var aabb: (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let cx = x + width / 2
        let cy = y + height / 2
        let hw = width / 2
        let hh = height / 2

        guard rotation != 0 else {
            return (x, y, x + width, y + height)
        }

        let rad = rotation * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        let newHW = hw * cosA + hh * sinA
        let newHH = hw * sinA + hh * cosA
        return (cx - newHW, cy - newHH, cx + newHW, cy + newHH)
    }

    func resolvedDeviceBodyColor(default defaultColor: Color) -> Color {
        deviceBodyColorData?.color ?? defaultColor
    }

    func duplicated(offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CanvasShapeModel {
        var copy = self
        copy.id = UUID()
        copy.x += offsetX
        copy.y += offsetY
        return copy
    }

    static func defaultRectangle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .rectangle, x: centerX - 250, y: centerY - 200, width: 500, height: 400, color: .orange)
    }

    static func defaultCircle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .circle, x: centerX - 200, y: centerY - 200, width: 400, height: 400, color: .purple)
    }

    static func defaultStar(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .star, x: centerX - 200, y: centerY - 200, width: 400, height: 400, color: .yellow, starPointCount: defaultStarPointCount)
    }

    static func defaultText(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        let text = "Your awesome new feature here!"
        let fontSize: CGFloat = 110
        let fontWeight: Int = 700
        let width: CGFloat = 700
        let nsFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: nsFont]
        )
        let height = ceil(boundingRect.height) + fontSize * 0.2
        return CanvasShapeModel(
            type: .text, x: centerX - width / 2, y: centerY - height / 2, width: width, height: height,
            color: .white, text: text, fontSize: fontSize, fontWeight: fontWeight, textAlign: .center
        )
    }

    static func defaultImage(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .image, x: centerX - 250, y: centerY - 250, width: 500, height: 500, color: .gray)
    }

    static func defaultSvg(centerX: CGFloat, centerY: CGFloat, svgContent: String, size: CGSize) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .svg, x: centerX - size.width / 2, y: centerY - size.height / 2,
            width: size.width, height: size.height,
            color: .white, svgContent: svgContent, svgUseColor: false
        )
    }

    var resolvedDeviceFrame: DeviceFrame? {
        guard let frameId = deviceFrameId else { return nil }
        return DeviceFrameCatalog.frame(for: frameId)
    }

    /// Resolved base dimensions accounting for real device frames.
    var resolvedBaseDimensions: (width: CGFloat, height: CGFloat) {
        if let frame = resolvedDeviceFrame {
            return frame.baseDimensions
        }
        return (deviceCategory ?? .iphone).baseDimensions
    }

    /// Adjusts width to match the correct aspect ratio for the current device type.
    /// Optionally re-centers horizontally at `centerX`.
    mutating func adjustToDeviceAspectRatio(centerX: CGFloat? = nil) {
        let base = resolvedBaseDimensions
        let aspect = base.width / base.height
        width = height * aspect
        if let cx = centerX {
            x = cx - width / 2
        }
    }

    static func defaultDevice(centerX: CGFloat, centerY: CGFloat, templateHeight: CGFloat = 2688, category: DeviceCategory = .iphone) -> CanvasShapeModel {
        let dims = category.baseDimensions
        // Device should fill ~80% of template height, like typical App Store screenshots
        let h = templateHeight * 0.8
        let scale = h / dims.height
        let w = dims.width * scale
        return CanvasShapeModel(
            type: .device, x: centerX - w / 2, y: centerY - h / 2,
            width: w, height: h,
            color: .clear, deviceCategory: category
        )
    }

    /// Creates a device shape using the row's default device settings.
    /// If `detectedCategory` is provided, it overrides the row default category
    /// (but a row-level real device frame still takes priority).
    static func defaultDeviceFromRow(_ row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat, detectedCategory: DeviceCategory? = nil) -> CanvasShapeModel {
        let category = detectedCategory ?? row.defaultDeviceCategory ?? .iphone
        var shape = defaultDevice(
            centerX: centerX, centerY: centerY,
            templateHeight: row.templateHeight,
            category: category
        )
        // Only apply the row's default frame if it matches the detected category
        if let frameId = row.defaultDeviceFrameId,
           let frame = DeviceFrameCatalog.frame(for: frameId),
           detectedCategory == nil || frame.fallbackCategory == detectedCategory {
            shape.deviceCategory = frame.fallbackCategory
            shape.deviceFrameId = frame.id
            shape.adjustToDeviceAspectRatio(centerX: centerX)
        }
        return shape
    }

    /// Creates a default shape for the given type, placed at the specified center.
    /// Returns `nil` for `.svg` which requires additional parameters.
    static func defaultShape(for type: ShapeType, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel? {
        switch type {
        case .rectangle: return defaultRectangle(centerX: centerX, centerY: centerY)
        case .circle: return defaultCircle(centerX: centerX, centerY: centerY)
        case .star: return defaultStar(centerX: centerX, centerY: centerY)
        case .text: return defaultText(centerX: centerX, centerY: centerY)
        case .image: return defaultImage(centerX: centerX, centerY: centerY)
        case .device: return defaultDeviceFromRow(row, centerX: centerX, centerY: centerY)
        case .svg: return nil
        }
    }
}
