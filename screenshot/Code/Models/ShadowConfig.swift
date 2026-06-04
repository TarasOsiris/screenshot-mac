import SwiftUI

/// Configurable drop shadow for a canvas shape (currently used by device shapes).
///
/// All geometry values (`radius`, `offsetX`, `offsetY`) are in **model space** —
/// the render layer multiplies them by `displayScale`, so the editor (display
/// scale) and export (scale 1.0) stay in parity, mirroring `displayOutlineWidth`.
///
/// All fields are optional and only encoded when set, so existing projects saved
/// before this feature decode to an empty config (`enabled == nil` → no shadow).
struct ShadowConfig: Codable, Equatable {
    static let defaultColor: Color = .black
    static let defaultRadius: CGFloat = 40
    static let defaultOffsetX: CGFloat = 0
    static let defaultOffsetY: CGFloat = 30
    static let defaultOpacity: Double = 0.30

    static let radiusRange: ClosedRange<Double> = 0...150
    static let offsetRange: ClosedRange<Double> = -100...100
    static let opacityRange: ClosedRange<Double> = 0...1

    var enabled: Bool?
    var colorData: CodableColor?
    var radius: CGFloat?
    var offsetX: CGFloat?
    var offsetY: CGFloat?
    var opacity: Double?

    enum CodingKeys: String, CodingKey {
        case enabled = "en"
        case colorData = "c"
        case radius = "r"
        case offsetX = "ox"
        case offsetY = "oy"
        case opacity = "op"
    }

    init(
        enabled: Bool? = nil,
        color: Color? = nil,
        radius: CGFloat? = nil,
        offsetX: CGFloat? = nil,
        offsetY: CGFloat? = nil,
        opacity: Double? = nil
    ) {
        self.enabled = enabled
        self.colorData = color.map { CodableColor($0) }
        self.radius = radius
        self.offsetX = offsetX
        self.offsetY = offsetY
        self.opacity = opacity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        colorData = try c.decodeIfPresent(CodableColor.self, forKey: .colorData)
        radius = try c.decodeIfPresent(CGFloat.self, forKey: .radius)
        offsetX = try c.decodeIfPresent(CGFloat.self, forKey: .offsetX)
        offsetY = try c.decodeIfPresent(CGFloat.self, forKey: .offsetY)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(colorData, forKey: .colorData)
        try c.encodeIfPresent(radius, forKey: .radius)
        try c.encodeIfPresent(offsetX, forKey: .offsetX)
        try c.encodeIfPresent(offsetY, forKey: .offsetY)
        try c.encodeIfPresent(opacity, forKey: .opacity)
    }

    /// `true` when no field is set — used to skip encoding and to gate the reset button.
    var isEmpty: Bool {
        enabled == nil && colorData == nil && radius == nil
            && offsetX == nil && offsetY == nil && opacity == nil
    }

    /// Whether the shadow should actually be drawn.
    var isActive: Bool { enabled == true }

    var color: Color {
        get { colorData?.color ?? Self.defaultColor }
        set { colorData = CodableColor(newValue) }
    }

    var resolvedColor: Color { colorData?.color ?? Self.defaultColor }
    var resolvedRadius: CGFloat { radius ?? Self.defaultRadius }
    var resolvedOffsetX: CGFloat { offsetX ?? Self.defaultOffsetX }
    var resolvedOffsetY: CGFloat { offsetY ?? Self.defaultOffsetY }
    var resolvedOpacity: Double { opacity ?? Self.defaultOpacity }

    // MARK: - Presets

    enum Preset: String, CaseIterable, Identifiable {
        case soft, medium, strong
        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .soft: return "Soft"
            case .medium: return "Medium"
            case .strong: return "Strong"
            }
        }

        /// (radius, offsetY, opacity) — offsetX is 0; presets don't touch color.
        var values: (radius: CGFloat, offsetY: CGFloat, opacity: Double) {
            switch self {
            case .soft: return (24, 16, 0.18)
            case .medium: return (40, 30, 0.30)
            case .strong: return (70, 50, 0.45)
            }
        }
    }

    static func preset(_ preset: Preset, color: Color = defaultColor) -> ShadowConfig {
        let v = preset.values
        return ShadowConfig(
            enabled: true,
            color: color,
            radius: v.radius,
            offsetX: 0,
            offsetY: v.offsetY,
            opacity: v.opacity
        )
    }

    static let soft = preset(.soft)
    static let medium = preset(.medium)
    static let strong = preset(.strong)

    /// The preset whose values match the current config, or `nil` if it's been customized.
    var matchingPreset: Preset? {
        guard abs(resolvedOffsetX) < 0.001 else { return nil }
        return Preset.allCases.first { p in
            let v = p.values
            return abs(resolvedRadius - v.radius) < 0.001
                && abs(resolvedOffsetY - v.offsetY) < 0.001
                && abs(resolvedOpacity - v.opacity) < 0.001
        }
    }
}
