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

// MARK: - Background Style

enum BackgroundStyle: String, Codable, CaseIterable {
    case color
    case gradient
}

struct GradientConfig: Codable, Equatable {
    var color1Data: CodableColor
    var color2Data: CodableColor
    var angle: Double // degrees

    init(color1: Color = Color(red: 0.4, green: 0.49, blue: 0.92),
         color2: Color = Color(red: 0.46, green: 0.29, blue: 0.64),
         angle: Double = 135) {
        self.color1Data = CodableColor(color1)
        self.color2Data = CodableColor(color2)
        self.angle = angle
    }

    var color1: Color {
        get { color1Data.color }
        set { color1Data = CodableColor(newValue) }
    }

    var color2: Color {
        get { color2Data.color }
        set { color2Data = CodableColor(newValue) }
    }

    private var radians: Double {
        (angle - 90) * .pi / 180
    }

    var startPoint: UnitPoint {
        UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    var endPoint: UnitPoint {
        UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    var linearGradient: LinearGradient {
        LinearGradient(colors: [color1, color2], startPoint: startPoint, endPoint: endPoint)
    }
}

struct GradientPreset: Identifiable {
    let id = UUID()
    let label: String
    let color1: Color
    let color2: Color
    let angle: Double

    var config: GradientConfig {
        GradientConfig(color1: color1, color2: color2, angle: angle)
    }
}

let gradientPresets: [GradientPreset] = [
    GradientPreset(label: "Ocean", color1: Color(red: 0.4, green: 0.49, blue: 0.92), color2: Color(red: 0.46, green: 0.29, blue: 0.64), angle: 135),
    GradientPreset(label: "Sunset", color1: Color(red: 0.94, green: 0.58, blue: 0.98), color2: Color(red: 0.96, green: 0.34, blue: 0.42), angle: 135),
    GradientPreset(label: "Peach", color1: Color(red: 0.96, green: 0.83, blue: 0.40), color2: Color(red: 0.99, green: 0.63, blue: 0.52), angle: 135),
    GradientPreset(label: "Mint", color1: Color(red: 0.63, green: 0.77, blue: 0.99), color2: Color(red: 0.76, green: 0.91, blue: 0.98), angle: 135),
    GradientPreset(label: "Berry", color1: Color(red: 0.63, green: 0.55, blue: 0.82), color2: Color(red: 0.98, green: 0.76, blue: 0.92), angle: 135),
    GradientPreset(label: "Flame", color1: Color(red: 0.97, green: 0.21, blue: 0.0), color2: Color(red: 0.98, green: 0.83, blue: 0.14), angle: 135),
    GradientPreset(label: "Sky", color1: Color(red: 0.54, green: 0.97, blue: 1.0), color2: Color(red: 0.40, green: 0.65, blue: 1.0), angle: 135),
    GradientPreset(label: "Forest", color1: Color(red: 0.07, green: 0.60, blue: 0.56), color2: Color(red: 0.22, green: 0.94, blue: 0.49), angle: 135),
    GradientPreset(label: "Night", color1: Color(red: 0.06, green: 0.13, blue: 0.15), color2: Color(red: 0.17, green: 0.33, blue: 0.39), angle: 135),
    GradientPreset(label: "Rose", color1: Color(red: 0.93, green: 0.61, blue: 0.65), color2: Color(red: 1.0, green: 0.87, blue: 0.88), angle: 135),
    GradientPreset(label: "Indigo", color1: Color(red: 0.26, green: 0.22, blue: 0.79), color2: Color(red: 0.39, green: 0.40, blue: 0.95), angle: 135),
    GradientPreset(label: "Emerald", color1: Color(red: 0.02, green: 0.59, blue: 0.41), color2: Color(red: 0.20, green: 0.83, blue: 0.60), angle: 135),
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
    var screenshotFileName: String?

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
        deviceBodyColor: Color? = nil,
        screenshotFileName: String? = nil
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
        self.screenshotFileName = screenshotFileName
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
            deviceBodyColor: deviceBodyColorData?.color,
            screenshotFileName: screenshotFileName
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
    var backgroundStyle: BackgroundStyle
    var gradientConfig: GradientConfig
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
        backgroundStyle: BackgroundStyle = .color,
        gradientConfig: GradientConfig = GradientConfig(),
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
        self.backgroundStyle = backgroundStyle
        self.gradientConfig = gradientConfig
        self.showDevice = showDevice
        self.showBorders = showBorders
        self.shapes = shapes
    }

    enum CodingKeys: String, CodingKey {
        case id, label, templates, templateWidth, templateHeight
        case backgroundColorData, backgroundStyle, gradientConfig
        case showDevice, showBorders, shapes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        templates = try c.decode([ScreenshotTemplate].self, forKey: .templates)
        templateWidth = try c.decode(CGFloat.self, forKey: .templateWidth)
        templateHeight = try c.decode(CGFloat.self, forKey: .templateHeight)
        backgroundColorData = try c.decode(CodableColor.self, forKey: .backgroundColorData)
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .color
        gradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .gradientConfig) ?? GradientConfig()
        showDevice = try c.decodeIfPresent(Bool.self, forKey: .showDevice) ?? true
        showBorders = try c.decodeIfPresent(Bool.self, forKey: .showBorders) ?? true
        shapes = try c.decodeIfPresent([CanvasShapeModel].self, forKey: .shapes) ?? []
    }

    var bgColor: Color {
        get { backgroundColorData.color }
        set { backgroundColorData = CodableColor(newValue) }
    }

    @ViewBuilder
    var backgroundFill: some View {
        switch backgroundStyle {
        case .color:
            Rectangle().fill(bgColor)
        case .gradient:
            Rectangle().fill(gradientConfig.linearGradient)
        }
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
