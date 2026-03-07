import Foundation
import SwiftUI

enum ShapeType: String, Codable, CaseIterable {
    case rectangle
    case circle
    case text
    case image
    case device
    case svg
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
    /// iPhone 17: 71.5 x 149.6 mm at scale 3.077 px/mm -> 220 x 460.
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
    var italic: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?

    // Image properties
    var imageFileName: String?

    // Device properties
    var deviceCategory: DeviceCategory?
    var deviceBodyColorData: CodableColor?
    var screenshotFileName: String?

    // SVG properties
    var svgContent: String?
    var svgUseColor: Bool?

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
        italic: Bool? = nil,
        letterSpacing: CGFloat? = nil,
        lineSpacing: CGFloat? = nil,
        imageFileName: String? = nil,
        deviceCategory: DeviceCategory? = nil,
        deviceBodyColor: Color? = nil,
        screenshotFileName: String? = nil,
        svgContent: String? = nil,
        svgUseColor: Bool? = nil
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
        self.italic = italic
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.imageFileName = imageFileName
        self.deviceCategory = deviceCategory
        self.deviceBodyColorData = deviceBodyColor.map { CodableColor($0) }
        self.screenshotFileName = screenshotFileName
        self.svgContent = svgContent
        self.svgUseColor = svgUseColor
    }

    /// Used as a fallback when a Binding's get is called after the shape has been removed.
    static let placeholder = CanvasShapeModel(type: .rectangle)

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
            italic: italic, letterSpacing: letterSpacing, lineSpacing: lineSpacing,
            imageFileName: imageFileName,
            deviceCategory: deviceCategory,
            deviceBodyColor: deviceBodyColorData?.color,
            screenshotFileName: screenshotFileName,
            svgContent: svgContent,
            svgUseColor: svgUseColor
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

    static func defaultSvg(centerX: CGFloat, centerY: CGFloat, svgContent: String, size: CGSize) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .svg, x: centerX - size.width / 2, y: centerY - size.height / 2,
            width: size.width, height: size.height,
            color: .white, svgContent: svgContent, svgUseColor: false
        )
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
