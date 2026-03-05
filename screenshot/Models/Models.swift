import Foundation
import SwiftUI

// MARK: - Binding Extension

extension Binding {
    func onSet(_ action: @escaping () -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0; action() }
        )
    }
}

struct ScreenshotSize: Identifiable {
    let id = UUID()
    let width: CGFloat
    let height: CGFloat

    var label: String {
        "\(Int(width)) × \(Int(height))px"
    }

    var isLandscape: Bool {
        width > height
    }
}

struct DisplayCategory: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let sizes: [ScreenshotSize]
}

let displayCategories: [DisplayCategory] = [
    DisplayCategory(
        name: "iPhone 6.5\" Display",
        icon: "iphone",
        sizes: [
            ScreenshotSize(width: 1242, height: 2688),
            ScreenshotSize(width: 2688, height: 1242),
            ScreenshotSize(width: 1284, height: 2778),
            ScreenshotSize(width: 2778, height: 1284),
        ]
    ),
    DisplayCategory(
        name: "iPad 13\" Display",
        icon: "ipad",
        sizes: [
            ScreenshotSize(width: 2064, height: 2752),
            ScreenshotSize(width: 2752, height: 2064),
            ScreenshotSize(width: 2048, height: 2732),
            ScreenshotSize(width: 2732, height: 2048),
        ]
    ),
]

// MARK: - Codable Color

struct CodableColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    init(_ color: Color) {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.red = Double(nsColor.redComponent)
        self.green = Double(nsColor.greenComponent)
        self.blue = Double(nsColor.blueComponent)
        self.opacity = Double(nsColor.alphaComponent)
    }

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Project

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - ScreenshotTemplate

struct ScreenshotTemplate: Identifiable, Codable {
    let id: UUID
    var backgroundColor: CodableColor

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = CodableColor(backgroundColor)
    }

    var bgColor: Color {
        get { backgroundColor.color }
        set { backgroundColor = CodableColor(newValue) }
    }
}

// MARK: - Shape

enum ShapeType: String, Codable, CaseIterable {
    case rectangle
    case circle
    case text
    case image
    case device
}

enum DeviceCategory: String, Codable, CaseIterable {
    case iphone

    var label: String {
        switch self {
        case .iphone: "iPhone"
        }
    }

    var icon: String {
        switch self {
        case .iphone: "iphone"
        }
    }

    /// Base dimensions for the device frame (body including bezels).
    /// iPhone 17: 71.5 × 149.6 mm at scale 3.077 px/mm → 220 × 460.
    var baseDimensions: (width: CGFloat, height: CGFloat) {
        switch self {
        case .iphone: (220, 460)
        }
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
    let id: UUID
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
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?

    // Image properties
    var imageFileName: String?

    // Device properties
    var deviceCategory: DeviceCategory?
    var deviceBodyColorData: CodableColor?

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
        fontSize: CGFloat? = nil,
        fontWeight: Int? = nil,
        textAlign: TextAlign? = nil,
        imageFileName: String? = nil,
        deviceCategory: DeviceCategory? = nil,
        deviceBodyColor: Color? = nil
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
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textAlign = textAlign
        self.imageFileName = imageFileName
        self.deviceCategory = deviceCategory
        self.deviceBodyColorData = deviceBodyColor.map { CodableColor($0) }
    }

    var color: Color {
        get { colorData.color }
        set { colorData = CodableColor(newValue) }
    }

    var deviceBodyColor: Color {
        get { deviceBodyColorData?.color ?? Color(red: 0.11, green: 0.11, blue: 0.12) }
        set { deviceBodyColorData = CodableColor(newValue) }
    }

    func duplicated(offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CanvasShapeModel {
        CanvasShapeModel(
            type: type, x: x + offsetX, y: y + offsetY,
            width: width, height: height,
            rotation: rotation, borderRadius: borderRadius,
            color: color, opacity: opacity,
            text: text, fontSize: fontSize,
            fontWeight: fontWeight, textAlign: textAlign,
            imageFileName: imageFileName,
            deviceCategory: deviceCategory,
            deviceBodyColor: deviceBodyColorData?.color
        )
    }

    static func defaultRectangle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .rectangle, x: centerX - 150, y: centerY - 125, width: 300, height: 250, color: .orange)
    }

    static func defaultCircle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .circle, x: centerX - 100, y: centerY - 100, width: 200, height: 200, color: .purple)
    }

    static func defaultText(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .text, x: centerX - 200, y: centerY - 42, width: 400, height: 84,
            color: .white, text: "Your text here", fontSize: 72, fontWeight: 700, textAlign: .center
        )
    }

    static func defaultImage(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .image, x: centerX - 150, y: centerY - 150, width: 300, height: 300, color: .gray)
    }

    static func defaultDevice(centerX: CGFloat, centerY: CGFloat, templateHeight: CGFloat = 2688) -> CanvasShapeModel {
        let dims = DeviceCategory.iphone.baseDimensions
        // Device should fill ~80% of template height, like typical App Store screenshots
        let h = templateHeight * 0.8
        let scale = h / dims.height
        let w = dims.width * scale
        return CanvasShapeModel(
            type: .device, x: centerX - w / 2, y: centerY - h / 2,
            width: w, height: h,
            color: .clear, deviceCategory: .iphone,
            deviceBodyColor: Color(red: 0.11, green: 0.11, blue: 0.12)
        )
    }
}

// MARK: - ScreenshotRow

struct ScreenshotRow: Identifiable, Codable {
    let id: UUID
    var label: String
    var templates: [ScreenshotTemplate]
    var templateWidth: CGFloat
    var templateHeight: CGFloat
    var backgroundColorData: CodableColor
    var showDevice: Bool
    var showBorders: Bool
    var shapes: [CanvasShapeModel]

    init(
        id: UUID = UUID(),
        label: String = "Screenshot 1",
        templates: [ScreenshotTemplate] = [],
        templateWidth: CGFloat = 1242,
        templateHeight: CGFloat = 2688,
        bgColor: Color = .blue,
        showDevice: Bool = true,
        showBorders: Bool = true,
        shapes: [CanvasShapeModel] = []
    ) {
        self.id = id
        self.label = label
        self.templates = templates
        self.templateWidth = templateWidth
        self.templateHeight = templateHeight
        self.backgroundColorData = CodableColor(bgColor)
        self.showDevice = showDevice
        self.showBorders = showBorders
        self.shapes = shapes
    }

    enum CodingKeys: String, CodingKey {
        case id, label, templates, templateWidth, templateHeight
        case backgroundColorData, showDevice, showBorders, shapes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        templates = try c.decode([ScreenshotTemplate].self, forKey: .templates)
        templateWidth = try c.decode(CGFloat.self, forKey: .templateWidth)
        templateHeight = try c.decode(CGFloat.self, forKey: .templateHeight)
        backgroundColorData = try c.decode(CodableColor.self, forKey: .backgroundColorData)
        showDevice = try c.decodeIfPresent(Bool.self, forKey: .showDevice) ?? true
        showBorders = try c.decodeIfPresent(Bool.self, forKey: .showBorders) ?? true
        shapes = try c.decodeIfPresent([CanvasShapeModel].self, forKey: .shapes) ?? []
    }

    var bgColor: Color {
        get { backgroundColorData.color }
        set { backgroundColorData = CodableColor(newValue) }
    }

    func displayScale(zoom: CGFloat = 1.0) -> CGFloat {
        let maxDisplayHeight: CGFloat = 500
        return min(1, maxDisplayHeight / templateHeight) * zoom
    }

    func displayWidth(zoom: CGFloat = 1.0) -> CGFloat {
        templateWidth * displayScale(zoom: zoom)
    }

    func displayHeight(zoom: CGFloat = 1.0) -> CGFloat {
        templateHeight * displayScale(zoom: zoom)
    }

    func totalDisplayWidth(zoom: CGFloat = 1.0) -> CGFloat {
        displayWidth(zoom: zoom) * CGFloat(templates.count)
    }

    var resolutionLabel: String {
        "\(Int(templateWidth))x\(Int(templateHeight))"
    }

    var activeShapes: [CanvasShapeModel] {
        shapes.filter { showDevice || $0.type != .device }
    }

    func visibleShapes(forTemplateAt index: Int) -> [CanvasShapeModel] {
        let tLeft = CGFloat(index) * templateWidth
        let tRight = tLeft + templateWidth
        return shapes.filter { s in
            let sRight = s.x + s.width
            return sRight > tLeft && s.x < tRight
        }
    }
}

// MARK: - Persistence data

struct ProjectIndex: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
}

struct ProjectData: Codable {
    var rows: [ScreenshotRow]
}
