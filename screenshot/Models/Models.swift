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

enum DeviceCategory: String, CaseIterable, Identifiable, Codable {
    case iphone = "iPhone"
    case ipad = "iPad"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iphone: "iphone"
        case .ipad: "ipad"
        }
    }
}

struct DevicePreset: Identifiable {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    let category: DeviceCategory
}

let devicePresets: [DevicePreset] = [
    DevicePreset(name: "iPhone 6.7\"", width: 1290, height: 2796, category: .iphone),
    DevicePreset(name: "iPhone 6.5\"", width: 1284, height: 2778, category: .iphone),
    DevicePreset(name: "iPhone 5.5\"", width: 1242, height: 2208, category: .iphone),
    DevicePreset(name: "iPad 12.9\"", width: 2048, height: 2732, category: .ipad),
    DevicePreset(name: "iPad 11\"", width: 1668, height: 2388, category: .ipad),
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
    var textAlign: String?

    // Image properties
    var imageFileName: String?

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
        textAlign: String? = nil,
        imageFileName: String? = nil
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
    }

    var color: Color {
        get { colorData.color }
        set { colorData = CodableColor(newValue) }
    }

    func duplicated(offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CanvasShapeModel {
        CanvasShapeModel(
            type: type, x: x + offsetX, y: y + offsetY,
            width: width, height: height,
            rotation: rotation, borderRadius: borderRadius,
            color: color, opacity: opacity,
            text: text, fontSize: fontSize,
            fontWeight: fontWeight, textAlign: textAlign,
            imageFileName: imageFileName
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
            color: .white, text: "Your text here", fontSize: 72, fontWeight: 700, textAlign: "center"
        )
    }

    static func defaultImage(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .image, x: centerX - 150, y: centerY - 150, width: 300, height: 300, color: .gray)
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
        templateWidth: CGFloat = 1290,
        templateHeight: CGFloat = 2796,
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

    var totalCanvasWidth: CGFloat {
        templateWidth * CGFloat(templates.count)
    }

    var totalDisplayWidth: CGFloat {
        displayWidth * CGFloat(templates.count)
    }

    var bgColor: Color {
        get { backgroundColorData.color }
        set { backgroundColorData = CodableColor(newValue) }
    }

    var displayScale: CGFloat {
        let maxDisplayHeight: CGFloat = 500
        return min(1, maxDisplayHeight / templateHeight)
    }

    var displayWidth: CGFloat {
        templateWidth * displayScale
    }

    var displayHeight: CGFloat {
        templateHeight * displayScale
    }

    var resolutionLabel: String {
        "\(Int(templateWidth))x\(Int(templateHeight))"
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
