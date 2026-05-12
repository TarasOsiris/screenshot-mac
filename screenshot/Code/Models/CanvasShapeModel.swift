import Foundation
import SwiftUI

struct CanvasShapeModel: Identifiable, Codable {
    static let deviceMinSize: CGFloat = 200
    static let defaultDeviceBodyColor = Color.black
    static let defaultDevice3DBodyColor = Color(white: 0x91 / 255.0)
    static let defaultPixel9BodyColor = Color(white: 0xA9 / 255.0)
    static let defaultDeviceModelPitch: Double = -22
    static let defaultDeviceModelYaw: Double = -14
    static let defaultFontSize: CGFloat = 72
    static let fontSizePresets: [Int] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96, 128, 144, 192, 256]
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
    var richText: String?  // Base64-encoded RTF data for per-range styling
    var fontName: String?
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?
    var textVerticalAlign: TextVerticalAlign?
    var italic: Bool?
    var uppercase: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?

    // Image properties
    var imageFileName: String?

    // Device properties
    var deviceCategory: DeviceCategory?
    var deviceBodyColorData: CodableColor?
    var deviceFrameId: String?
    var screenshotFileName: String?
    var devicePitch: Double?
    var deviceYaw: Double?
    var deviceBodyMaterial: DeviceBodyMaterial?
    var deviceLighting: DeviceLighting?

    // SVG properties
    var svgContent: String?
    var svgUseColor: Bool?

    // Outline properties
    var outlineColorData: CodableColor?
    var outlineWidth: CGFloat?

    // Star properties
    var starPointCount: Int?

    // Fill style (for rectangle, circle, star)
    var fillStyle: BackgroundStyle?
    var fillGradientConfig: GradientConfig?
    var fillImageConfig: BackgroundImageConfig?

    // Clipping
    var clipToTemplate: Bool?

    // Lock — when true, the shape is frozen: no drag, resize, rotate, or edit.
    var isLocked: Bool?

    enum CodingKeys: String, CodingKey {
        case id, x, y
        case type = "t"
        case width = "w", height = "h"
        case rotation = "rot", borderRadius = "br"
        case colorData = "c", opacity = "o"
        case text = "txt", richText = "rt", fontName = "fn", fontSize = "fs", fontWeight = "fw"
        case textAlign = "ta", textVerticalAlign = "tva", italic = "it", uppercase = "uc"
        case letterSpacing = "ls", lineSpacing = "lns", lineHeightMultiple = "lhm"
        case imageFileName = "ifn"
        case deviceCategory = "dc", deviceBodyColorData = "dbc"
        case deviceFrameId = "dfi", screenshotFileName = "sfn"
        case devicePitch = "dpt", deviceYaw = "dyw", deviceBodyMaterial = "dbm", deviceLighting = "dlt"
        case svgContent = "svg", svgUseColor = "suc"
        case outlineColorData = "olc", outlineWidth = "olw"
        case starPointCount = "spc"
        case fillStyle = "fst"
        case fillGradientConfig = "fgc"
        case fillImageConfig = "fic"
        case clipToTemplate = "ct"
        case isLocked = "lk"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(ShapeType.self, forKey: .type)
        x = try c.decode(CGFloat.self, forKey: .x)
        y = try c.decode(CGFloat.self, forKey: .y)
        width = try c.decode(CGFloat.self, forKey: .width)
        height = try c.decode(CGFloat.self, forKey: .height)
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        borderRadius = try c.decodeIfPresent(CGFloat.self, forKey: .borderRadius) ?? 0
        colorData = try c.decode(CodableColor.self, forKey: .colorData)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        text = try c.decodeIfPresent(String.self, forKey: .text)
        richText = try c.decodeIfPresent(String.self, forKey: .richText)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName)
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize)
        fontWeight = try c.decodeIfPresent(Int.self, forKey: .fontWeight)
        textAlign = try c.decodeIfPresent(TextAlign.self, forKey: .textAlign)
        textVerticalAlign = try c.decodeIfPresent(TextVerticalAlign.self, forKey: .textVerticalAlign)
        italic = try c.decodeIfPresent(Bool.self, forKey: .italic)
        uppercase = try c.decodeIfPresent(Bool.self, forKey: .uppercase)
        letterSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .letterSpacing)
        lineSpacing = try c.decodeIfPresent(CGFloat.self, forKey: .lineSpacing)
        lineHeightMultiple = try c.decodeIfPresent(CGFloat.self, forKey: .lineHeightMultiple)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        deviceCategory = try c.decodeIfPresent(DeviceCategory.self, forKey: .deviceCategory)
        deviceBodyColorData = try c.decodeIfPresent(CodableColor.self, forKey: .deviceBodyColorData)
        deviceFrameId = try c.decodeIfPresent(String.self, forKey: .deviceFrameId)
        screenshotFileName = try c.decodeIfPresent(String.self, forKey: .screenshotFileName)
        devicePitch = try c.decodeIfPresent(Double.self, forKey: .devicePitch)
        deviceYaw = try c.decodeIfPresent(Double.self, forKey: .deviceYaw)
        deviceBodyMaterial = try c.decodeIfPresent(DeviceBodyMaterial.self, forKey: .deviceBodyMaterial)
        deviceLighting = try c.decodeIfPresent(DeviceLighting.self, forKey: .deviceLighting)
        svgContent = try c.decodeIfPresent(String.self, forKey: .svgContent)
        svgUseColor = try c.decodeIfPresent(Bool.self, forKey: .svgUseColor)
        outlineColorData = try c.decodeIfPresent(CodableColor.self, forKey: .outlineColorData)
        outlineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .outlineWidth)
        starPointCount = try c.decodeIfPresent(Int.self, forKey: .starPointCount)
        fillStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .fillStyle)
        fillGradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .fillGradientConfig)
        fillImageConfig = try c.decodeIfPresent(BackgroundImageConfig.self, forKey: .fillImageConfig)
        clipToTemplate = try c.decodeIfPresent(Bool.self, forKey: .clipToTemplate)
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        if rotation != 0 { try c.encode(rotation, forKey: .rotation) }
        if borderRadius != 0 { try c.encode(borderRadius, forKey: .borderRadius) }
        try c.encode(colorData, forKey: .colorData)
        if opacity != 1.0 { try c.encode(opacity, forKey: .opacity) }
        // Text properties
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(richText, forKey: .richText)
        try c.encodeIfPresent(fontName, forKey: .fontName)
        try c.encodeIfPresent(fontSize, forKey: .fontSize)
        try c.encodeIfPresent(fontWeight, forKey: .fontWeight)
        try c.encodeIfPresent(textAlign, forKey: .textAlign)
        try c.encodeIfPresent(textVerticalAlign, forKey: .textVerticalAlign)
        try c.encodeIfPresent(italic, forKey: .italic)
        try c.encodeIfPresent(uppercase, forKey: .uppercase)
        try c.encodeIfPresent(letterSpacing, forKey: .letterSpacing)
        try c.encodeIfPresent(lineSpacing, forKey: .lineSpacing)
        try c.encodeIfPresent(lineHeightMultiple, forKey: .lineHeightMultiple)
        // Image
        try c.encodeIfPresent(imageFileName, forKey: .imageFileName)
        // Device
        try c.encodeIfPresent(deviceCategory, forKey: .deviceCategory)
        try c.encodeIfPresent(deviceBodyColorData, forKey: .deviceBodyColorData)
        try c.encodeIfPresent(deviceFrameId, forKey: .deviceFrameId)
        try c.encodeIfPresent(screenshotFileName, forKey: .screenshotFileName)
        if abs(resolvedDevicePitch) > 0.001 { try c.encode(resolvedDevicePitch, forKey: .devicePitch) }
        if abs(resolvedDeviceYaw) > 0.001 { try c.encode(resolvedDeviceYaw, forKey: .deviceYaw) }
        if let material = deviceBodyMaterial, !material.isEmpty {
            try c.encode(material, forKey: .deviceBodyMaterial)
        }
        if let lighting = deviceLighting, !lighting.isEmpty {
            try c.encode(lighting, forKey: .deviceLighting)
        }
        // SVG
        try c.encodeIfPresent(svgContent, forKey: .svgContent)
        try c.encodeIfPresent(svgUseColor, forKey: .svgUseColor)
        // Outline
        try c.encodeIfPresent(outlineColorData, forKey: .outlineColorData)
        try c.encodeIfPresent(outlineWidth, forKey: .outlineWidth)
        // Star
        try c.encodeIfPresent(starPointCount, forKey: .starPointCount)
        // Fill style
        try c.encodeIfPresent(fillStyle, forKey: .fillStyle)
        try c.encodeIfPresent(fillGradientConfig, forKey: .fillGradientConfig)
        try c.encodeIfPresent(fillImageConfig, forKey: .fillImageConfig)
        // Clipping
        try c.encodeIfPresent(clipToTemplate, forKey: .clipToTemplate)
        // Lock
        try c.encodeIfPresent(isLocked, forKey: .isLocked)
    }

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
        textVerticalAlign: TextVerticalAlign? = nil,
        italic: Bool? = nil,
        uppercase: Bool? = nil,
        letterSpacing: CGFloat? = nil,
        lineSpacing: CGFloat? = nil,
        lineHeightMultiple: CGFloat? = nil,
        imageFileName: String? = nil,
        deviceCategory: DeviceCategory? = nil,
        deviceBodyColor: Color? = nil,
        deviceFrameId: String? = nil,
        screenshotFileName: String? = nil,
        devicePitch: Double? = nil,
        deviceYaw: Double? = nil,
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
        self.richText = nil
        self.fontName = fontName
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.textAlign = textAlign
        self.textVerticalAlign = textVerticalAlign
        self.italic = italic
        self.uppercase = uppercase
        self.letterSpacing = letterSpacing
        self.lineSpacing = lineSpacing
        self.lineHeightMultiple = lineHeightMultiple
        self.imageFileName = imageFileName
        self.deviceCategory = deviceCategory
        self.deviceBodyColorData = deviceBodyColor.map { CodableColor($0) }
        self.deviceFrameId = deviceFrameId
        self.screenshotFileName = screenshotFileName
        self.devicePitch = devicePitch
        self.deviceYaw = deviceYaw
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
        [screenshotFileName, imageFileName, fillImageConfig?.fileName].compactMap { $0 }
    }

    var resolvedIsLocked: Bool { isLocked ?? false }

    var resolvedFillStyle: BackgroundStyle {
        fillStyle ?? .color
    }

    @ViewBuilder
    func fillView(image: NSImage? = nil, modelSize: CGSize? = nil) -> some View {
        switch resolvedFillStyle {
        case .color:
            Rectangle().fill(color)
        case .gradient:
            (fillGradientConfig ?? GradientConfig()).gradientFill
        case .image:
            if let image, let config = fillImageConfig {
                ZStack {
                    Rectangle().fill(color)
                    BackgroundImageView(image: image, config: config, modelSize: modelSize)
                }
            } else {
                Rectangle().fill(color)
            }
        }
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
        if let override = deviceBodyColorData?.color { return override }
        if supportsDeviceModelRotation { return Self.defaultDevice3DBodyColor }
        if deviceCategory == .pixel9 { return Self.defaultPixel9BodyColor }
        return defaultColor
    }

    var supportsDeviceModelRotation: Bool {
        type == .device && (resolvedDeviceFrame?.isModelBacked == true)
    }

    var resolvedDevicePitch: Double {
        guard supportsDeviceModelRotation else { return 0 }
        return devicePitch ?? resolvedDeviceFrame?.modelSpec?.defaultPitch ?? Self.defaultDeviceModelPitch
    }

    var resolvedDeviceYaw: Double {
        guard supportsDeviceModelRotation else { return 0 }
        return deviceYaw ?? resolvedDeviceFrame?.modelSpec?.defaultYaw ?? Self.defaultDeviceModelYaw
    }

    mutating func resetDeviceModelRotation() {
        devicePitch = nil
        deviceYaw = nil
    }

    var resolvedDeviceBodyMaterial: DeviceBodyMaterial {
        deviceBodyMaterial ?? DeviceBodyMaterial()
    }

    mutating func resetDeviceBodyMaterial() {
        deviceBodyMaterial = nil
    }

    var resolvedDeviceLighting: DeviceLighting {
        deviceLighting ?? DeviceLighting()
    }

    mutating func resetDeviceLighting() {
        deviceLighting = nil
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
        let text = String(localized: "Your awesome new feature here!")
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

    /// Selects an abstract device category (no specific frame).
    /// When switching to `.invisible`, pass the current screenshot image size so the frame
    /// adapts its aspect ratio to the image. A nice default corner radius is also applied.
    mutating func selectAbstractDevice(_ category: DeviceCategory, screenshotImageSize: CGSize? = nil) {
        deviceFrameId = nil
        deviceCategory = category
        deviceBodyColorData = nil
        resetDeviceModelRotation()
        resetDeviceBodyMaterial()
        resetDeviceLighting()
        if category == .invisible {
            if borderRadius == 0 {
                borderRadius = 40
            }
            if let imageSize = screenshotImageSize {
                adaptToImageAspectRatio(imageSize)
            }
        } else {
            adjustToDeviceAspectRatio()
        }
    }

    /// Adjusts width to match the given image's aspect ratio, keeping the shape centered horizontally.
    mutating func adaptToImageAspectRatio(_ imageSize: CGSize) {
        guard imageSize.width > 0 && imageSize.height > 0 else { return }
        let aspect = imageSize.width / imageSize.height
        let centerX = x + width / 2
        width = height * aspect
        x = centerX - width / 2
    }

    /// Selects a specific device frame from the catalog.
    mutating func selectRealFrame(_ frame: DeviceFrame) {
        deviceCategory = frame.fallbackCategory
        deviceFrameId = frame.id
        if !frame.isModelBacked {
            resetDeviceModelRotation()
            resetDeviceBodyMaterial()
            resetDeviceLighting()
        }
        adjustToDeviceAspectRatio()
    }

    /// Adjusts the shape to match the correct aspect ratio for the current device type.
    /// Preserves the longer of the existing dimensions so an orientation flip keeps the
    /// shape's visual size — only the short side and orientation change. Re-centers on Y;
    /// optionally re-centers horizontally at `centerX`.
    /// Invisible frames skip aspect ratio enforcement — they keep their current dimensions.
    mutating func adjustToDeviceAspectRatio(centerX: CGFloat? = nil) {
        if deviceCategory == .invisible && deviceFrameId == nil {
            if let cx = centerX { x = cx - width / 2 }
            return
        }
        let base = resolvedBaseDimensions
        let aspect = base.width / base.height
        let oldCenterY = y + height / 2
        let longSide = max(width, height)
        let shortSide = longSide * min(aspect, 1 / aspect)
        (width, height) = aspect >= 1 ? (longSide, shortSide) : (shortSide, longSide)
        if let cx = centerX {
            x = cx - width / 2
        }
        y = oldCenterY - height / 2
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

    func extractTextStyle() -> TextStyle {
        TextStyle(
            fontName: fontName,
            fontSize: fontSize,
            fontWeight: fontWeight,
            textAlign: textAlign,
            textVerticalAlign: textVerticalAlign,
            italic: italic,
            uppercase: uppercase,
            letterSpacing: letterSpacing,
            lineSpacing: lineSpacing,
            lineHeightMultiple: lineHeightMultiple,
            colorData: colorData,
            opacity: opacity
        )
    }

    mutating func applyTextStyle(_ style: TextStyle) {
        fontName = style.fontName
        fontSize = style.fontSize
        fontWeight = style.fontWeight
        textAlign = style.textAlign
        textVerticalAlign = style.textVerticalAlign
        italic = style.italic
        uppercase = style.uppercase
        letterSpacing = style.letterSpacing
        lineSpacing = style.lineSpacing
        lineHeightMultiple = style.lineHeightMultiple
        colorData = style.colorData
        opacity = style.opacity
        richText = nil
    }

    var hasRichText: Bool { richText != nil }

    /// Re-applies only the caller's changes relative to `oldBase` onto `newBase`.
    /// This is used when a discrete edit was prepared from a stale snapshot while a
    /// continuous edit was still in flight for the same shape.
    func rebased(from oldBase: CanvasShapeModel, onto newBase: CanvasShapeModel) -> CanvasShapeModel {
        var result = newBase

        if type != oldBase.type { result.type = type }
        if x != oldBase.x { result.x = x }
        if y != oldBase.y { result.y = y }
        if width != oldBase.width { result.width = width }
        if height != oldBase.height { result.height = height }
        if rotation != oldBase.rotation { result.rotation = rotation }
        if borderRadius != oldBase.borderRadius { result.borderRadius = borderRadius }
        if colorData != oldBase.colorData { result.colorData = colorData }
        if opacity != oldBase.opacity { result.opacity = opacity }

        if text != oldBase.text { result.text = text }
        if richText != oldBase.richText { result.richText = richText }
        if fontName != oldBase.fontName { result.fontName = fontName }
        if fontSize != oldBase.fontSize { result.fontSize = fontSize }
        if fontWeight != oldBase.fontWeight { result.fontWeight = fontWeight }
        if textAlign != oldBase.textAlign { result.textAlign = textAlign }
        if textVerticalAlign != oldBase.textVerticalAlign { result.textVerticalAlign = textVerticalAlign }
        if italic != oldBase.italic { result.italic = italic }
        if uppercase != oldBase.uppercase { result.uppercase = uppercase }
        if letterSpacing != oldBase.letterSpacing { result.letterSpacing = letterSpacing }
        if lineSpacing != oldBase.lineSpacing { result.lineSpacing = lineSpacing }
        if lineHeightMultiple != oldBase.lineHeightMultiple { result.lineHeightMultiple = lineHeightMultiple }

        if imageFileName != oldBase.imageFileName { result.imageFileName = imageFileName }
        if deviceCategory != oldBase.deviceCategory { result.deviceCategory = deviceCategory }
        if deviceBodyColorData != oldBase.deviceBodyColorData { result.deviceBodyColorData = deviceBodyColorData }
        if deviceFrameId != oldBase.deviceFrameId { result.deviceFrameId = deviceFrameId }
        if screenshotFileName != oldBase.screenshotFileName { result.screenshotFileName = screenshotFileName }
        if devicePitch != oldBase.devicePitch { result.devicePitch = devicePitch }
        if deviceYaw != oldBase.deviceYaw { result.deviceYaw = deviceYaw }
        if deviceBodyMaterial != oldBase.deviceBodyMaterial { result.deviceBodyMaterial = deviceBodyMaterial }
        if deviceLighting != oldBase.deviceLighting { result.deviceLighting = deviceLighting }

        if svgContent != oldBase.svgContent { result.svgContent = svgContent }
        if svgUseColor != oldBase.svgUseColor { result.svgUseColor = svgUseColor }

        if outlineColorData != oldBase.outlineColorData { result.outlineColorData = outlineColorData }
        if outlineWidth != oldBase.outlineWidth { result.outlineWidth = outlineWidth }
        if starPointCount != oldBase.starPointCount { result.starPointCount = starPointCount }

        if fillStyle != oldBase.fillStyle { result.fillStyle = fillStyle }
        if fillGradientConfig != oldBase.fillGradientConfig { result.fillGradientConfig = fillGradientConfig }
        if fillImageConfig != oldBase.fillImageConfig { result.fillImageConfig = fillImageConfig }

        if clipToTemplate != oldBase.clipToTemplate { result.clipToTemplate = clipToTemplate }
        if isLocked != oldBase.isLocked { result.isLocked = isLocked }

        return result
    }
}
