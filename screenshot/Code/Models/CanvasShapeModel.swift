import Foundation
import SwiftUI

struct CanvasShapeModel: Identifiable, Codable, Equatable {
    nonisolated static let deviceMinSize: CGFloat = 200
    nonisolated static let shapeMinSize: CGFloat = 20
    nonisolated static let defaultDeviceBodyColor = Color.black
    nonisolated static let defaultDevice3DBodyColor = Color(white: 0x91 / 255.0)
    nonisolated static let defaultPixel9BodyColor = Color(white: 0xA9 / 255.0)
    nonisolated static let defaultDeviceModelPitch: Double = -22
    nonisolated static let defaultDeviceModelYaw: Double = -14
    nonisolated static let defaultFontSize: CGFloat = 72
    nonisolated static let fontSizePresets: [Int] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96, 128, 144, 192, 256]
    nonisolated static let defaultStarPointCount = 5
    nonisolated static let defaultOutlineColor: Color = .black
    nonisolated static let defaultOutlineWidth: CGFloat = 4

    // MARK: Universal geometry
    var id: UUID
    var type: ShapeType
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var borderRadius: CGFloat
    var colorData: CodableColor

    /// Backing storage for the two properties whose range is an invariant rather than a
    /// convention. Every writer — the rotate handle, the typed field, a keypath binding, the MCP
    /// `update_shape` patch, the decoder — goes through the computed pair below, so none of them
    /// has to remember. `private` is file-scoped, and everything that writes them lives in this file.
    private var storedRotation: Double = 0
    private var storedOpacity: Double = 1.0

    /// Degrees, always folded into 0..<360. Still a `var`, so `\.rotation` stays a
    /// `WritableKeyPath` and the generic `shapeBinding`/`multiShapeBinding` keep working.
    nonisolated var rotation: Double {
        get { storedRotation }
        set { storedRotation = Self.normalizedRotation(newValue) }
    }

    /// Always within 0...1.
    nonisolated var opacity: Double {
        get { storedOpacity }
        set { storedOpacity = min(max(newValue, 0), 1) }
    }

    // MARK: Type-specific field groups
    // Storage is grouped by shape type; the flat properties below are computed passthroughs so
    // the persisted JSON (via the flat CodingKeys), the `shape.text`/`shape.fontSize` API, and the
    // `\.keyPath` shape bindings are all unchanged. Payloads are `nonisolated` because `encode`/
    // `init(from:)` run off the main actor during saves.
    var textPayload = TextPayload()
    var textBackgroundPayload = TextBackgroundPayload()
    var devicePayload = DevicePayload()
    var fillPayload = FillPayload()
    var outlinePayload = OutlinePayload()

    // Ungrouped type-specific fields (no cohesive cluster).
    var imageFileName: String?
    /// Zoom and pan of an image shape's picture; nil is the centered aspect fill.
    var imageCrop: ImageCrop?
    var svgContent: String?
    var svgUseColor: Bool?
    var starPointCount: Int?
    var clipToTemplate: Bool?
    /// Lock — when true, the shape is frozen: no drag, resize, rotate, or edit.
    var isLocked: Bool?

    nonisolated struct TextPayload: Equatable {
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
        /// Catalog key this text shape sources its string from. `nil` means it owns its own string
        /// (key = `id`). When set, the shape shares another string's base text + translations.
        var translationKey: String?
        var shrinkToFit: Bool?
    }

    /// A rounded-rect plate behind a `.text` shape's glyphs.
    nonisolated struct TextBackgroundPayload: Equatable {
        var colorData: CodableColor?
        var cornerRadius: CGFloat?
        var padding: CGFloat?
        var outlineColorData: CodableColor?
        var outlineWidth: CGFloat?
        var opacity: Double?
    }

    // Unlike the sibling payloads this can't be a `nonisolated struct`: its ShadowConfig /
    // DeviceBodyMaterial / DeviceLighting members have main-actor-isolated Equatable. The
    // nonisolated init lets the `= DevicePayload()` default be built from the off-main Codable path.
    struct DevicePayload: Equatable {
        nonisolated init() {}
        var category: DeviceCategory?
        var bodyColorData: CodableColor?
        var frameId: String?
        var screenshotFileName: String?
        var pitch: Double?
        var yaw: Double?
        var bodyMaterial: DeviceBodyMaterial?
        var lighting: DeviceLighting?
        var hideCameraCutout: Bool?
        var shadow: ShadowConfig?
    }

    /// Fill style (for rectangle, circle, star).
    nonisolated struct FillPayload: Equatable {
        var style: BackgroundStyle?
        var gradientConfig: GradientConfig?
        var imageConfig: BackgroundImageConfig?
    }

    nonisolated struct OutlinePayload: Equatable {
        var colorData: CodableColor?
        var width: CGFloat?
    }

    // MARK: Flat passthroughs (preserve the pre-existing API, keypaths, and on-disk keys)
    nonisolated var text: String? { get { textPayload.text } set { textPayload.text = newValue } }
    nonisolated var richText: String? { get { textPayload.richText } set { textPayload.richText = newValue } }
    nonisolated var fontName: String? { get { textPayload.fontName } set { textPayload.fontName = newValue } }
    nonisolated var fontSize: CGFloat? { get { textPayload.fontSize } set { textPayload.fontSize = newValue } }
    nonisolated var fontWeight: Int? { get { textPayload.fontWeight } set { textPayload.fontWeight = newValue } }
    nonisolated var textAlign: TextAlign? { get { textPayload.textAlign } set { textPayload.textAlign = newValue } }
    nonisolated var textVerticalAlign: TextVerticalAlign? { get { textPayload.textVerticalAlign } set { textPayload.textVerticalAlign = newValue } }
    nonisolated var italic: Bool? { get { textPayload.italic } set { textPayload.italic = newValue } }
    nonisolated var uppercase: Bool? { get { textPayload.uppercase } set { textPayload.uppercase = newValue } }
    nonisolated var letterSpacing: CGFloat? { get { textPayload.letterSpacing } set { textPayload.letterSpacing = newValue } }
    nonisolated var lineSpacing: CGFloat? { get { textPayload.lineSpacing } set { textPayload.lineSpacing = newValue } }
    nonisolated var lineHeightMultiple: CGFloat? { get { textPayload.lineHeightMultiple } set { textPayload.lineHeightMultiple = newValue } }
    nonisolated var translationKey: String? { get { textPayload.translationKey } set { textPayload.translationKey = newValue } }
    nonisolated var shrinkToFit: Bool? { get { textPayload.shrinkToFit } set { textPayload.shrinkToFit = newValue } }

    nonisolated var textBackgroundColorData: CodableColor? { get { textBackgroundPayload.colorData } set { textBackgroundPayload.colorData = newValue } }
    nonisolated var textBackgroundCornerRadius: CGFloat? { get { textBackgroundPayload.cornerRadius } set { textBackgroundPayload.cornerRadius = newValue } }
    nonisolated var textBackgroundPadding: CGFloat? { get { textBackgroundPayload.padding } set { textBackgroundPayload.padding = newValue } }
    nonisolated var textBackgroundOutlineColorData: CodableColor? { get { textBackgroundPayload.outlineColorData } set { textBackgroundPayload.outlineColorData = newValue } }
    nonisolated var textBackgroundOutlineWidth: CGFloat? { get { textBackgroundPayload.outlineWidth } set { textBackgroundPayload.outlineWidth = newValue } }
    nonisolated var textBackgroundOpacity: Double? { get { textBackgroundPayload.opacity } set { textBackgroundPayload.opacity = newValue } }

    nonisolated var deviceCategory: DeviceCategory? { get { devicePayload.category } set { devicePayload.category = newValue } }
    nonisolated var deviceBodyColorData: CodableColor? { get { devicePayload.bodyColorData } set { devicePayload.bodyColorData = newValue } }
    nonisolated var deviceFrameId: String? { get { devicePayload.frameId } set { devicePayload.frameId = newValue } }
    nonisolated var screenshotFileName: String? { get { devicePayload.screenshotFileName } set { devicePayload.screenshotFileName = newValue } }
    nonisolated var devicePitch: Double? { get { devicePayload.pitch } set { devicePayload.pitch = newValue } }
    nonisolated var deviceYaw: Double? { get { devicePayload.yaw } set { devicePayload.yaw = newValue } }
    nonisolated var deviceBodyMaterial: DeviceBodyMaterial? { get { devicePayload.bodyMaterial } set { devicePayload.bodyMaterial = newValue } }
    nonisolated var deviceLighting: DeviceLighting? { get { devicePayload.lighting } set { devicePayload.lighting = newValue } }
    nonisolated var hideCameraCutout: Bool? { get { devicePayload.hideCameraCutout } set { devicePayload.hideCameraCutout = newValue } }
    nonisolated var shadow: ShadowConfig? { get { devicePayload.shadow } set { devicePayload.shadow = newValue } }

    nonisolated var fillStyle: BackgroundStyle? { get { fillPayload.style } set { fillPayload.style = newValue } }
    nonisolated var fillGradientConfig: GradientConfig? { get { fillPayload.gradientConfig } set { fillPayload.gradientConfig = newValue } }
    nonisolated var fillImageConfig: BackgroundImageConfig? { get { fillPayload.imageConfig } set { fillPayload.imageConfig = newValue } }

    nonisolated var outlineColorData: CodableColor? { get { outlinePayload.colorData } set { outlinePayload.colorData = newValue } }
    nonisolated var outlineWidth: CGFloat? { get { outlinePayload.width } set { outlinePayload.width = newValue } }

    enum CodingKeys: String, CodingKey {
        case id, x, y
        case type = "t"
        case width = "w", height = "h"
        case rotation = "rot", borderRadius = "br"
        case colorData = "c", opacity = "o"
        case text = "txt", richText = "rt", fontName = "fn", fontSize = "fs", fontWeight = "fw"
        case textAlign = "ta", textVerticalAlign = "tva", italic = "it", uppercase = "uc"
        case letterSpacing = "ls", lineSpacing = "lns", lineHeightMultiple = "lhm"
        case translationKey = "tk", shrinkToFit = "stf"
        case imageFileName = "ifn", imageCrop = "icr"
        case deviceCategory = "dc", deviceBodyColorData = "dbc"
        case deviceFrameId = "dfi", screenshotFileName = "sfn"
        case devicePitch = "dpt", deviceYaw = "dyw", deviceBodyMaterial = "dbm", deviceLighting = "dlt"
        case hideCameraCutout = "hcc"
        case shadow = "shd"
        case svgContent = "svg", svgUseColor = "suc"
        case outlineColorData = "olc", outlineWidth = "olw"
        case textBackgroundColorData = "tbc", textBackgroundCornerRadius = "tbr", textBackgroundPadding = "tbp"
        case textBackgroundOutlineColorData = "tboc", textBackgroundOutlineWidth = "tbow"
        case textBackgroundOpacity = "tba"
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
        storedRotation = Self.normalizedRotation(try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0)
        borderRadius = try c.decodeIfPresent(CGFloat.self, forKey: .borderRadius) ?? 0
        colorData = try c.decode(CodableColor.self, forKey: .colorData)
        storedOpacity = min(max(try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0, 0), 1)
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
        translationKey = try c.decodeIfPresent(String.self, forKey: .translationKey)
        shrinkToFit = try c.decodeIfPresent(Bool.self, forKey: .shrinkToFit)
        imageFileName = try c.decodeIfPresent(String.self, forKey: .imageFileName)
        imageCrop = try c.decodeIfPresent(ImageCrop.self, forKey: .imageCrop)
        deviceCategory = try c.decodeIfPresent(DeviceCategory.self, forKey: .deviceCategory)
        deviceBodyColorData = try c.decodeIfPresent(CodableColor.self, forKey: .deviceBodyColorData)
        deviceFrameId = try c.decodeIfPresent(String.self, forKey: .deviceFrameId)
        screenshotFileName = try c.decodeIfPresent(String.self, forKey: .screenshotFileName)
        devicePitch = try c.decodeIfPresent(Double.self, forKey: .devicePitch)
        deviceYaw = try c.decodeIfPresent(Double.self, forKey: .deviceYaw)
        deviceBodyMaterial = try c.decodeIfPresent(DeviceBodyMaterial.self, forKey: .deviceBodyMaterial)
        deviceLighting = try c.decodeIfPresent(DeviceLighting.self, forKey: .deviceLighting)
        hideCameraCutout = try c.decodeIfPresent(Bool.self, forKey: .hideCameraCutout)
        shadow = try c.decodeIfPresent(ShadowConfig.self, forKey: .shadow)
        svgContent = try c.decodeIfPresent(String.self, forKey: .svgContent)
        svgUseColor = try c.decodeIfPresent(Bool.self, forKey: .svgUseColor)
        outlineColorData = try c.decodeIfPresent(CodableColor.self, forKey: .outlineColorData)
        outlineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .outlineWidth)
        textBackgroundColorData = try c.decodeIfPresent(CodableColor.self, forKey: .textBackgroundColorData)
        textBackgroundCornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .textBackgroundCornerRadius)
        textBackgroundPadding = try c.decodeIfPresent(CGFloat.self, forKey: .textBackgroundPadding)
        textBackgroundOutlineColorData = try c.decodeIfPresent(CodableColor.self, forKey: .textBackgroundOutlineColorData)
        textBackgroundOutlineWidth = try c.decodeIfPresent(CGFloat.self, forKey: .textBackgroundOutlineWidth)
        textBackgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .textBackgroundOpacity)
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
        try c.encodeIfPresent(translationKey, forKey: .translationKey)
        if shrinkToFit == true { try c.encode(true, forKey: .shrinkToFit) }
        try c.encodeIfPresent(imageFileName, forKey: .imageFileName)
        if let imageCrop, !imageCrop.isIdentity { try c.encode(imageCrop, forKey: .imageCrop) }
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
        try c.encodeIfPresent(hideCameraCutout, forKey: .hideCameraCutout)
        if let shadow, !shadow.isEmpty {
            try c.encode(shadow, forKey: .shadow)
        }
        try c.encodeIfPresent(svgContent, forKey: .svgContent)
        try c.encodeIfPresent(svgUseColor, forKey: .svgUseColor)
        try c.encodeIfPresent(outlineColorData, forKey: .outlineColorData)
        try c.encodeIfPresent(outlineWidth, forKey: .outlineWidth)
        try c.encodeIfPresent(textBackgroundColorData, forKey: .textBackgroundColorData)
        if let radius = textBackgroundCornerRadius, radius != 0 { try c.encode(radius, forKey: .textBackgroundCornerRadius) }
        if let padding = textBackgroundPadding, padding != 0 { try c.encode(padding, forKey: .textBackgroundPadding) }
        try c.encodeIfPresent(textBackgroundOutlineColorData, forKey: .textBackgroundOutlineColorData)
        try c.encodeIfPresent(textBackgroundOutlineWidth, forKey: .textBackgroundOutlineWidth)
        if let o = textBackgroundOpacity, o != 1.0 { try c.encode(o, forKey: .textBackgroundOpacity) }
        try c.encodeIfPresent(starPointCount, forKey: .starPointCount)
        try c.encodeIfPresent(fillStyle, forKey: .fillStyle)
        try c.encodeIfPresent(fillGradientConfig, forKey: .fillGradientConfig)
        try c.encodeIfPresent(fillImageConfig, forKey: .fillImageConfig)
        try c.encodeIfPresent(clipToTemplate, forKey: .clipToTemplate)
        try c.encodeIfPresent(isLocked, forKey: .isLocked)
    }

    nonisolated init(
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
        textBackgroundColor: Color? = nil,
        textBackgroundCornerRadius: CGFloat? = nil,
        textBackgroundPadding: CGFloat? = nil,
        textBackgroundOutlineColor: Color? = nil,
        textBackgroundOutlineWidth: CGFloat? = nil,
        textBackgroundOpacity: Double? = nil,
        starPointCount: Int? = nil,
        clipToTemplate: Bool? = nil,
        shadow: ShadowConfig? = nil,
        translationKey: String? = nil
    ) {
        self.id = id
        self.type = type
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.storedRotation = Self.normalizedRotation(rotation)
        self.borderRadius = borderRadius
        self.colorData = CodableColor(color)
        self.storedOpacity = min(max(opacity, 0), 1)
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
        self.textBackgroundColorData = textBackgroundColor.map { CodableColor($0) }
        self.textBackgroundCornerRadius = textBackgroundCornerRadius
        self.textBackgroundPadding = textBackgroundPadding
        self.textBackgroundOutlineColorData = textBackgroundOutlineColor.map { CodableColor($0) }
        self.textBackgroundOutlineWidth = textBackgroundOutlineWidth
        self.textBackgroundOpacity = textBackgroundOpacity
        self.starPointCount = starPointCount
        self.clipToTemplate = clipToTemplate
        self.shadow = shadow
        self.translationKey = translationKey
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

    static let defaultTextBackgroundColor: Color = .black
    static let defaultTextBackgroundOutlineColor: Color = defaultOutlineColor
    static let defaultTextBackgroundOutlineWidth: CGFloat = defaultOutlineWidth

    var textBackgroundColor: Color? {
        get { textBackgroundColorData?.color }
        set { textBackgroundColorData = newValue.map { CodableColor($0) } }
    }

    var textBackgroundOutlineColor: Color? {
        get { textBackgroundOutlineColorData?.color }
        set { textBackgroundOutlineColorData = newValue.map { CodableColor($0) } }
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
    nonisolated var allImageFileNames: [String] {
        [screenshotFileName, imageFileName, fillImageConfig?.fileName].compactMap { $0 }
    }

    var resolvedIsLocked: Bool { isLocked ?? false }

    /// True when `ids` matches at least one shape and every match is locked. Lives on the model so
    /// the Edit menu, the properties bar and the row canvas all answer identically — the canvas
    /// must derive this from its own shapes rather than an `AppState` property that reads `rows`
    /// and would register `\AppState.rows` in every row's tracking scope (SCREENSHOT-BRO-W).
    static func areFullyLocked(_ shapes: [CanvasShapeModel], ids: Set<UUID>) -> Bool {
        guard !ids.isEmpty else { return false }
        var anyMatch = false
        for shape in shapes where ids.contains(shape.id) {
            if !shape.resolvedIsLocked { return false }
            anyMatch = true
        }
        return anyMatch
    }

    var resolvedFillStyle: BackgroundStyle {
        fillStyle ?? .color
    }

    var supportsCornerRadius: Bool {
        type == .rectangle || type == .image || (type == .device && deviceCategory == .invisible)
    }

    /// `ShapeType.supportsOutline` plus the invisible device, whose frame is drawn as an outline.
    var supportsOutlineEditing: Bool {
        type.supportsOutline || (type == .device && deviceCategory == .invisible)
    }

    /// Zoom over the aspect-fill fit; pan offsets are left for the renderer to re-clamp.
    var imageCropScale: Double {
        get { imageCrop?.scale ?? 1 }
        set {
            var crop = imageCrop ?? ImageCrop()
            crop.scale = min(max(newValue, ImageCrop.scaleRange.lowerBound), ImageCrop.scaleRange.upperBound)
            imageCrop = crop.isIdentity ? nil : crop
        }
    }

    func duplicated(offsetX: CGFloat = 0, offsetY: CGFloat = 0) -> CanvasShapeModel {
        var copy = self
        copy.id = UUID()
        copy.x += offsetX
        copy.y += offsetY
        return copy
    }
}
