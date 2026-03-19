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
        case showDevice = "sd", hiddenShapeTypes = "hst"
        case showBorders = "sb", shapes = "s", isLabelManuallySet = "lm"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.flexContainer()
        id = try c.decode(UUID.self, "id")
        label = try c.decode(String.self, "l", "label")
        templates = try c.decode([ScreenshotTemplate].self, "tp", "templates")
        templateWidth = try c.decode(CGFloat.self, "tw", "templateWidth")
        templateHeight = try c.decode(CGFloat.self, "th", "templateHeight")
        backgroundColorData = try c.decode(CodableColor.self, "bgc", "backgroundColorData")
        defaultDeviceBodyColorData = try c.opt(CodableColor.self, "ddbc", "defaultDeviceBodyColorData")
            ?? CodableColor(CanvasShapeModel.defaultDeviceBodyColor)
        // Legacy projects without this key default to .iphone; explicit null means "No device"
        if c.has("ddc", "defaultDeviceCategory") {
            defaultDeviceCategory = try c.opt(DeviceCategory.self, "ddc", "defaultDeviceCategory")
        } else {
            defaultDeviceCategory = .iphone
        }
        backgroundStyle = try c.opt(BackgroundStyle.self, "bgs", "backgroundStyle") ?? .color
        gradientConfig = try c.opt(GradientConfig.self, "gc", "gradientConfig") ?? GradientConfig()
        spanBackgroundAcrossRow = try c.opt(Bool.self, "span", "spanGradientAcrossRow", "spanBackgroundAcrossRow") ?? false
        backgroundImageConfig = try c.opt(BackgroundImageConfig.self, "bgic", "backgroundImageConfig") ?? BackgroundImageConfig()
        defaultDeviceFrameId = try c.opt(String.self, "ddfi", "defaultDeviceFrameId")
        // Migrate legacy showDevice bool into hiddenShapeTypes set
        var hidden = try c.opt(Set<ShapeType>.self, "hst", "hiddenShapeTypes") ?? []
        let showDevice = try c.opt(Bool.self, "sd", "showDevice") ?? true
        if !showDevice { hidden.insert(.device) }
        hiddenShapeTypes = hidden
        showBorders = try c.opt(Bool.self, "sb", "showBorders") ?? true
        shapes = try c.opt([CanvasShapeModel].self, "s", "shapes") ?? []
        isLabelManuallySet = try c.opt(Bool.self, "lm", "isLabelManuallySet") ?? false
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
        // Encode null explicitly so decoder can distinguish "no device" from missing key
        try c.encode(defaultDeviceCategory, forKey: .defaultDeviceCategory)
        if backgroundStyle != .color { try c.encode(backgroundStyle, forKey: .backgroundStyle) }
        if backgroundStyle == .gradient { try c.encode(gradientConfig, forKey: .gradientConfig) }
        if spanBackgroundAcrossRow { try c.encode(true, forKey: .spanBackgroundAcrossRow) }
        if backgroundStyle == .image { try c.encode(backgroundImageConfig, forKey: .backgroundImageConfig) }
        try c.encodeIfPresent(defaultDeviceFrameId, forKey: .defaultDeviceFrameId)
        if !hiddenShapeTypes.isEmpty { try c.encode(hiddenShapeTypes, forKey: .hiddenShapeTypes) }
        // Write showDevice for backward compatibility with older app versions
        if !showDevice { try c.encode(false, forKey: .showDevice) }
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
