import Foundation
import SwiftUI

struct ScreenshotRow: Identifiable, Codable, BackgroundFillable {
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
    func effectiveBackgroundFill(forTemplateAt index: Int) -> some View {
        let template = templates[index]
        if template.overrideBackground {
            template.backgroundFill
        } else {
            backgroundFill
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

    func templateCenterX(at index: Int) -> CGFloat {
        CGFloat(index) * templateWidth + templateWidth / 2
    }

    func visibleShapes(forTemplateAt index: Int) -> [CanvasShapeModel] {
        let tLeft = CGFloat(index) * templateWidth
        let tRight = tLeft + templateWidth
        return activeShapes.filter { s in
            let sRight = s.x + s.width
            return sRight > tLeft && s.x < tRight
        }
    }
}
