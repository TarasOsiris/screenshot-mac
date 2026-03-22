import Foundation
import SwiftUI

struct ScreenshotRow: Identifiable, Codable, BackgroundFillable {
    let id: UUID
    var label: String
    var templates: [ScreenshotTemplate]
    var templateWidth: CGFloat
    var templateHeight: CGFloat
    var backgroundColorData: CodableColor
    var defaultDeviceBodyColorData: CodableColor
    var defaultDeviceCategory: DeviceCategory?
    var backgroundStyle: BackgroundStyle
    var gradientConfig: GradientConfig
    var spanBackgroundAcrossRow: Bool
    var backgroundImageConfig: BackgroundImageConfig
    var defaultDeviceFrameId: String?
    var hiddenShapeTypes: Set<ShapeType>
    var showBorders: Bool
    var shapes: [CanvasShapeModel]
    var isLabelManuallySet: Bool

    init(
        id: UUID = UUID(),
        label: String = "Screenshot 1",
        templates: [ScreenshotTemplate] = [],
        templateWidth: CGFloat = 1242,
        templateHeight: CGFloat = 2688,
        bgColor: Color = .blue,
        defaultDeviceBodyColor: Color = CanvasShapeModel.defaultDeviceBodyColor,
        defaultDeviceCategory: DeviceCategory? = .iphone,
        backgroundStyle: BackgroundStyle = .color,
        gradientConfig: GradientConfig = GradientConfig(),
        spanBackgroundAcrossRow: Bool = false,
        backgroundImageConfig: BackgroundImageConfig = BackgroundImageConfig(),
        defaultDeviceFrameId: String? = nil,
        showDevice: Bool = true,
        hiddenShapeTypes: Set<ShapeType> = [],
        showBorders: Bool = true,
        shapes: [CanvasShapeModel] = [],
        isLabelManuallySet: Bool = false
    ) {
        self.id = id
        self.label = label
        self.templates = templates
        self.templateWidth = templateWidth
        self.templateHeight = templateHeight
        self.backgroundColorData = CodableColor(bgColor)
        self.defaultDeviceBodyColorData = CodableColor(defaultDeviceBodyColor)
        self.defaultDeviceCategory = defaultDeviceCategory
        self.backgroundStyle = backgroundStyle
        self.gradientConfig = gradientConfig
        self.spanBackgroundAcrossRow = spanBackgroundAcrossRow
        self.backgroundImageConfig = backgroundImageConfig
        self.defaultDeviceFrameId = defaultDeviceFrameId
        var hidden = hiddenShapeTypes
        if !showDevice { hidden.insert(.device) }
        self.hiddenShapeTypes = hidden
        self.showBorders = showBorders
        self.shapes = shapes
        self.isLabelManuallySet = isLabelManuallySet
    }

    enum CodingKeys: String, CodingKey {
        case id, label = "l", templates = "tp"
        case templateWidth = "tw", templateHeight = "th"
        case backgroundColorData = "bgc", defaultDeviceBodyColorData = "ddbc"
        case defaultDeviceCategory = "ddc"
        case backgroundStyle = "bgs", gradientConfig = "gc", backgroundImageConfig = "bgic"
        case spanBackgroundAcrossRow = "span"
        case defaultDeviceFrameId = "ddfi"
        case hiddenShapeTypes = "hst"
        case showBorders = "sb", shapes = "s", isLabelManuallySet = "lm"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        templates = try c.decode([ScreenshotTemplate].self, forKey: .templates)
        templateWidth = try c.decode(CGFloat.self, forKey: .templateWidth)
        templateHeight = try c.decode(CGFloat.self, forKey: .templateHeight)
        backgroundColorData = try c.decode(CodableColor.self, forKey: .backgroundColorData)
        defaultDeviceBodyColorData = try c.decodeIfPresent(CodableColor.self, forKey: .defaultDeviceBodyColorData)
            ?? CodableColor(CanvasShapeModel.defaultDeviceBodyColor)
        defaultDeviceCategory = try c.decode(DeviceCategory?.self, forKey: .defaultDeviceCategory)
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .color
        gradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .gradientConfig) ?? GradientConfig()
        spanBackgroundAcrossRow = try c.decodeIfPresent(Bool.self, forKey: .spanBackgroundAcrossRow) ?? false
        backgroundImageConfig = try c.decodeIfPresent(BackgroundImageConfig.self, forKey: .backgroundImageConfig) ?? BackgroundImageConfig()
        defaultDeviceFrameId = try c.decodeIfPresent(String.self, forKey: .defaultDeviceFrameId)
        hiddenShapeTypes = try c.decodeIfPresent(Set<ShapeType>.self, forKey: .hiddenShapeTypes) ?? []
        showBorders = try c.decodeIfPresent(Bool.self, forKey: .showBorders) ?? true
        shapes = try c.decodeIfPresent([CanvasShapeModel].self, forKey: .shapes) ?? []
        isLabelManuallySet = try c.decodeIfPresent(Bool.self, forKey: .isLabelManuallySet) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(label, forKey: .label)
        try c.encode(templates, forKey: .templates)
        try c.encode(templateWidth, forKey: .templateWidth)
        try c.encode(templateHeight, forKey: .templateHeight)
        try c.encode(backgroundColorData, forKey: .backgroundColorData)
        try c.encode(defaultDeviceBodyColorData, forKey: .defaultDeviceBodyColorData)
        try c.encode(defaultDeviceCategory, forKey: .defaultDeviceCategory)
        if backgroundStyle != .color { try c.encode(backgroundStyle, forKey: .backgroundStyle) }
        if backgroundStyle == .gradient { try c.encode(gradientConfig, forKey: .gradientConfig) }
        if spanBackgroundAcrossRow { try c.encode(true, forKey: .spanBackgroundAcrossRow) }
        if backgroundStyle == .image { try c.encode(backgroundImageConfig, forKey: .backgroundImageConfig) }
        try c.encodeIfPresent(defaultDeviceFrameId, forKey: .defaultDeviceFrameId)
        if !hiddenShapeTypes.isEmpty { try c.encode(hiddenShapeTypes, forKey: .hiddenShapeTypes) }
        if !showBorders { try c.encode(false, forKey: .showBorders) }
        try c.encode(shapes, forKey: .shapes)
        if isLabelManuallySet { try c.encode(true, forKey: .isLabelManuallySet) }
    }

    var bgColor: Color {
        get { backgroundColorData.color }
        set { backgroundColorData = CodableColor(newValue) }
    }

    var defaultDeviceBodyColor: Color {
        get { defaultDeviceBodyColorData.color }
        set { defaultDeviceBodyColorData = CodableColor(newValue) }
    }

    /// Whether the row background should span as one continuous fill across all templates.
    var isSpanningBackground: Bool {
        spanBackgroundAcrossRow && backgroundStyle != .color
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
        "\(Int(templateWidth))\u{00d7}\(Int(templateHeight))"
    }

    var showDevice: Bool {
        get { !hiddenShapeTypes.contains(.device) }
        set {
            if newValue { hiddenShapeTypes.remove(.device) }
            else { hiddenShapeTypes.insert(.device) }
        }
    }

    var activeShapes: [CanvasShapeModel] {
        hiddenShapeTypes.isEmpty ? shapes : shapes.filter { !hiddenShapeTypes.contains($0.type) }
    }

    func templateCenterX(at index: Int) -> CGFloat {
        CGFloat(index) * templateWidth + templateWidth / 2
    }

    var svgMaxDimension: CGFloat {
        min(templateWidth, templateHeight) * 0.4
    }

    /// Returns the template index a shape belongs to, based on its center X (rotation-invariant).
    func owningTemplateIndex(for shape: CanvasShapeModel) -> Int {
        let centerX = shape.x + shape.width / 2
        let index = Int(floor(centerX / templateWidth))
        return max(0, min(index, templates.count - 1))
    }

    func visibleShapes(forTemplateAt index: Int) -> [CanvasShapeModel] {
        let tLeft = CGFloat(index) * templateWidth
        let tRight = tLeft + templateWidth
        return activeShapes.filter { s in
            // Shapes clipped to their template only appear in the owning template
            if s.clipToTemplate == true {
                return owningTemplateIndex(for: s) == index
            }
            let bb = s.aabb
            return bb.maxX > tLeft && bb.minX < tRight
        }
    }
}
