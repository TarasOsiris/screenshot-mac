import Foundation

/// Per-shape lighting configuration for 3D device frames.
/// All fields are optional; missing values fall back to the SceneKit defaults
/// that shipped before this struct existed, so older projects render unchanged.
struct DeviceLighting: Codable, Equatable {
    static let defaultAmbientIntensity: Double = 520
    static let defaultKeyIntensity: Double = 1600
    static let defaultRimIntensity: Double = 900

    static let ambientIntensityRange: ClosedRange<Double> = 0...2000
    static let keyIntensityRange: ClosedRange<Double> = 0...4000
    static let rimIntensityRange: ClosedRange<Double> = 0...2500

    var ambientIntensity: Double?
    var keyIntensity: Double?
    var rimIntensity: Double?

    enum CodingKeys: String, CodingKey {
        case ambientIntensity = "ai"
        case keyIntensity = "ki"
        case rimIntensity = "ri"
    }

    init(ambientIntensity: Double? = nil, keyIntensity: Double? = nil, rimIntensity: Double? = nil) {
        self.ambientIntensity = ambientIntensity
        self.keyIntensity = keyIntensity
        self.rimIntensity = rimIntensity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ambientIntensity = try c.decodeIfPresent(Double.self, forKey: .ambientIntensity)
        keyIntensity = try c.decodeIfPresent(Double.self, forKey: .keyIntensity)
        rimIntensity = try c.decodeIfPresent(Double.self, forKey: .rimIntensity)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(ambientIntensity, forKey: .ambientIntensity)
        try c.encodeIfPresent(keyIntensity, forKey: .keyIntensity)
        try c.encodeIfPresent(rimIntensity, forKey: .rimIntensity)
    }

    var isEmpty: Bool {
        ambientIntensity == nil && keyIntensity == nil && rimIntensity == nil
    }

    var resolvedAmbientIntensity: Double { ambientIntensity ?? Self.defaultAmbientIntensity }
    var resolvedKeyIntensity: Double { keyIntensity ?? Self.defaultKeyIntensity }
    var resolvedRimIntensity: Double { rimIntensity ?? Self.defaultRimIntensity }
}
