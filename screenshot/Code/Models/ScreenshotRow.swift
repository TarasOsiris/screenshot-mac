import Foundation
import SwiftUI

struct ScreenshotRow: Identifiable, Codable, Equatable, BackgroundFillable {
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
    var backgroundBlur: Double
    var defaultDeviceFrameId: String?
    var hiddenShapeTypes: Set<ShapeType>
    var showBorders: Bool
    var shapes: [CanvasShapeModel]
    var isLabelManuallySet: Bool
    var isCollapsed: Bool
    var excludeFromAppStoreConnect: Bool

    /// User-facing label; falls back to "Untitled Row" when `label` is empty.
    var displayLabel: String { label.isEmpty ? String(localized: "Untitled Row") : label }

    var templateSize: CGSize { CGSize(width: templateWidth, height: templateHeight) }

    /// Returns a copy with templates whose ids appear in `excluded` removed.
    /// Returns nil when every template would be removed, so callers can drop empty rows.
    func filtering(excluding excluded: Set<UUID>) -> ScreenshotRow? {
        guard !excluded.isEmpty else { return self }
        var copy = self
        copy.templates = templates.filter { !excluded.contains($0.id) }
        return copy.templates.isEmpty ? nil : copy
    }

    init(
        id: UUID = UUID(),
        label: String = String(localized: "Screenshot 1"),
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
        backgroundBlur: Double = 0,
        defaultDeviceFrameId: String? = nil,
        showDevice: Bool = true,
        hiddenShapeTypes: Set<ShapeType> = [],
        showBorders: Bool = true,
        shapes: [CanvasShapeModel] = [],
        isLabelManuallySet: Bool = false,
        isCollapsed: Bool = false,
        excludeFromAppStoreConnect: Bool = false
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
        self.backgroundBlur = backgroundBlur
        self.defaultDeviceFrameId = defaultDeviceFrameId
        var hidden = hiddenShapeTypes
        if !showDevice { hidden.insert(.device) }
        self.hiddenShapeTypes = hidden
        self.showBorders = showBorders
        self.shapes = shapes
        self.isLabelManuallySet = isLabelManuallySet
        self.isCollapsed = isCollapsed
        self.excludeFromAppStoreConnect = excludeFromAppStoreConnect
    }

    enum CodingKeys: String, CodingKey {
        case id, label = "l", templates = "tp"
        case templateWidth = "tw", templateHeight = "th"
        case backgroundColorData = "bgc", defaultDeviceBodyColorData = "ddbc"
        case defaultDeviceCategory = "ddc"
        case backgroundStyle = "bgs", gradientConfig = "gc", backgroundImageConfig = "bgic"
        case spanBackgroundAcrossRow = "span"
        case backgroundBlur = "bgbl"
        case defaultDeviceFrameId = "ddfi"
        case hiddenShapeTypes = "hst"
        case showBorders = "sb", shapes = "s", isLabelManuallySet = "lm", isCollapsed = "col"
        case excludeFromAppStoreConnect = "exasc"
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        templates = try c.decode([ScreenshotTemplate].self, forKey: .templates)
        templateWidth = try c.decode(CGFloat.self, forKey: .templateWidth)
        templateHeight = try c.decode(CGFloat.self, forKey: .templateHeight)
        backgroundColorData = try c.decode(CodableColor.self, forKey: .backgroundColorData)
        defaultDeviceBodyColorData = try c.decodeIfPresent(CodableColor.self, forKey: .defaultDeviceBodyColorData)
            ?? CodableColor(CanvasShapeModel.defaultDeviceBodyColor)
        defaultDeviceCategory = try c.decodeIfPresent(DeviceCategory.self, forKey: .defaultDeviceCategory)
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .color
        gradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .gradientConfig) ?? GradientConfig()
        spanBackgroundAcrossRow = try c.decodeIfPresent(Bool.self, forKey: .spanBackgroundAcrossRow) ?? false
        backgroundImageConfig = try c.decodeIfPresent(BackgroundImageConfig.self, forKey: .backgroundImageConfig) ?? BackgroundImageConfig()
        backgroundBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
        defaultDeviceFrameId = try c.decodeIfPresent(String.self, forKey: .defaultDeviceFrameId)
        hiddenShapeTypes = try c.decodeIfPresent(Set<ShapeType>.self, forKey: .hiddenShapeTypes) ?? []
        showBorders = try c.decodeIfPresent(Bool.self, forKey: .showBorders) ?? true
        shapes = try c.decodeIfPresent([CanvasShapeModel].self, forKey: .shapes) ?? []
        isLabelManuallySet = try c.decodeIfPresent(Bool.self, forKey: .isLabelManuallySet) ?? false
        isCollapsed = try c.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        excludeFromAppStoreConnect = try c.decodeIfPresent(Bool.self, forKey: .excludeFromAppStoreConnect) ?? false
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
        // Configs persist even when their style is inactive: switching to Color and saving
        // must not lose a tuned gradient or orphan a background image file.
        if !gradientConfig.isVisuallyDefault { try c.encode(gradientConfig, forKey: .gradientConfig) }
        if spanBackgroundAcrossRow { try c.encode(true, forKey: .spanBackgroundAcrossRow) }
        if backgroundImageConfig != BackgroundImageConfig() { try c.encode(backgroundImageConfig, forKey: .backgroundImageConfig) }
        if backgroundBlur != 0 { try c.encode(backgroundBlur, forKey: .backgroundBlur) }
        try c.encodeIfPresent(defaultDeviceFrameId, forKey: .defaultDeviceFrameId)
        if !hiddenShapeTypes.isEmpty { try c.encode(hiddenShapeTypes, forKey: .hiddenShapeTypes) }
        if !showBorders { try c.encode(false, forKey: .showBorders) }
        try c.encode(shapes, forKey: .shapes)
        if isLabelManuallySet { try c.encode(true, forKey: .isLabelManuallySet) }
        if isCollapsed { try c.encode(true, forKey: .isCollapsed) }
        if excludeFromAppStoreConnect { try c.encode(true, forKey: .excludeFromAppStoreConnect) }
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

    /// The background image this row references. `backgroundImageConfig` outlives its style —
    /// switching to Color keeps the tuned config so toggling back doesn't lose it — so renderers
    /// and upload checks must pass `activeOnly: true`, or a file nothing draws counts as a missing
    /// resource and blocks the upload. Retention (orphan cleanup) wants the ungated reference.
    nonisolated func backgroundImageFileName(activeOnly: Bool) -> String? {
        guard !activeOnly || backgroundStyle == .image else { return nil }
        return backgroundImageConfig.fileName
    }

    /// True when anything in the background is blurred — the row itself or an enabled per-template
    /// override. The editor blurs with SwiftUI `.blur` and export with CIGaussianBlur, so these rows
    /// must preview through the export renderer instead of drawing the blur live.
    var hasBlurredBackground: Bool {
        backgroundBlur > 0 || templates.contains { $0.overrideBackground && $0.backgroundBlur > 0 }
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

    func templateOriginX(at index: Int) -> CGFloat {
        CGFloat(index) * templateWidth
    }

    /// Left edge of the template a shape belongs to — the origin its properties-bar X is relative to.
    func templateOriginX(for shape: CanvasShapeModel) -> CGFloat {
        templateOriginX(at: owningTemplateIndex(for: shape))
    }

    func templateCenterX(at index: Int) -> CGFloat {
        templateOriginX(at: index) + templateWidth / 2
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
        let tLeft = templateOriginX(at: index)
        let tRight = tLeft + templateWidth
        return activeShapes.filter { s in
            // Shapes clipped to their template only appear in the owning template
            if s.clipToTemplate == true {
                return owningTemplateIndex(for: s) == index
            }
            let bb = s.visualAABB
            return bb.maxX > tLeft && bb.minX < tRight
        }
    }

    /// Ids of the shapes a marquee `rect` (model space) touches. Sketch semantics: a shape the
    /// band merely grazes is selected, and locked shapes are never swept up — group drag, nudge
    /// and delete all skip them, so including them would report a count larger than what moves.
    /// Takes the candidates explicitly — the caller passes its locale-resolved array, which is
    /// not `self.shapes`.
    func shapeIds(intersecting rect: CGRect, among candidates: [CanvasShapeModel]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for shape in candidates where !shape.resolvedIsLocked {
            guard let bounds = selectableBounds(of: shape) else { continue }
            if Self.overlaps(rect, bounds) { ids.insert(shape.id) }
        }
        return ids
    }

    /// The topmost shape whose body contains `point` (model space) — **locked ones included**,
    /// since a locked shape still swallows the press. `candidates` is in draw order, so the search
    /// runs back to front and the frontmost shape wins, matching what the canvas ZStack shows.
    ///
    /// `replacingWith` substitutes live geometry for the matching candidate without allocating a
    /// replacement array. `predicate` narrows the search without a second pass — for a caller that
    /// wants the topmost shape of a particular kind rather than the topmost shape.
    func hitShape(
        at point: CGPoint,
        among candidates: [CanvasShapeModel],
        replacingWith transientShape: CanvasShapeModel? = nil,
        where predicate: (CanvasShapeModel) -> Bool = { _ in true }
    ) -> CanvasShapeModel? {
        for candidate in candidates.reversed() {
            let shape: CanvasShapeModel
            if let transientShape, transientShape.id == candidate.id {
                shape = transientShape
            } else {
                shape = candidate
            }
            if predicate(shape), contains(shape, at: point) { return shape }
        }
        return nil
    }

    /// True when `point` (model space) lands on `shape`, respecting its rotation and — when it
    /// clips to its column — that column's bounds.
    ///
    /// Unlike `selectableBounds`, this is the *precise* body rather than the bounding box, so a
    /// press in the empty corner of a tilted shape misses it. Opacity is deliberately not
    /// consulted: a fully transparent shape stays clickable, as it always has been.
    func contains(_ shape: CanvasShapeModel, at point: CGPoint) -> Bool {
        CanvasHitTesting.contains(
            point: point,
            rect: CGRect(x: shape.x, y: shape.y, width: shape.width, height: shape.height),
            rotationDegrees: shape.rotation,
            clip: shape.clipToTemplate == true
                ? CGRect(x: templateOriginX(for: shape), y: 0, width: templateWidth, height: templateHeight)
                : nil
        )
    }

    /// True when `point` (model space) lands on any shape. A marquee uses this to refuse to start
    /// on top of a shape: the shape's own drag has a larger activation threshold, so without it a
    /// sweep would win the gap between the two thresholds and rubber-band instead of touching it.
    func containsShape(
        at point: CGPoint,
        among candidates: [CanvasShapeModel],
        replacingWith transientShape: CanvasShapeModel? = nil
    ) -> Bool {
        hitShape(at: point, among: candidates, replacingWith: transientShape) != nil
    }

    /// A shape's model-space bounds as the canvas presents them: rotation-aware, and cut down to
    /// its own column when it clips there. Nil when clipping leaves nothing on screen.
    private func selectableBounds(of shape: CanvasShapeModel) -> CGRect? {
        let bb = shape.aabb
        let bounds = CGRect(x: bb.minX, y: bb.minY, width: bb.maxX - bb.minX, height: bb.maxY - bb.minY)
        guard shape.clipToTemplate == true else { return bounds }
        let tLeft = templateOriginX(for: shape)
        let clipped = bounds.intersection(
            CGRect(x: tLeft, y: 0, width: templateWidth, height: templateHeight)
        )
        return clipped.isNull ? nil : clipped
    }

    /// Inclusive overlap. Not `CGRect.intersects`, which reports false whenever either rect is
    /// empty — a perfectly horizontal or vertical sweep produces a zero-height/width band and
    /// would then select nothing.
    private static func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY
    }

    /// Fraction of a shape's width that must lie outside its owning column before the shape
    /// counts as deliberately spanning templates (rather than a tilted device or full-bleed
    /// image merely bleeding past the column edge).
    static let templateSpanThreshold: CGFloat = 1.0 / 3.0

    /// True when a meaningful share of the shape's horizontal extent lies outside its owning
    /// template — i.e. it deliberately straddles columns. Uses the unrotated extent
    /// (rotation-invariant, like `owningTemplateIndex`) so a tilted device whose AABB
    /// merely bleeds past the column edge still belongs to its column.
    func spansMultipleTemplates(_ shape: CanvasShapeModel) -> Bool {
        if shape.clipToTemplate == true { return false }
        guard shape.width > 0 else { return false }
        let tLeft = templateOriginX(for: shape)
        let outside = max(0, tLeft - shape.x) + max(0, shape.x + shape.width - (tLeft + templateWidth))
        return outside / shape.width > Self.templateSpanThreshold
    }

    /// Inverse of `visibleShapes(forTemplateAt:)`: shapes that belong to this template's column.
    /// Operates over `shapes` (not `activeShapes`) since callers like deletion must consider hidden shapes too.
    func shapesContained(inTemplateAt index: Int) -> [CanvasShapeModel] {
        shapes.filter { !spansMultipleTemplates($0) && owningTemplateIndex(for: $0) == index }
    }
}
