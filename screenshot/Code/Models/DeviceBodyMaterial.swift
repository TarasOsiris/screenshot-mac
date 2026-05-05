import Foundation

/// Lighting model used for the 3D device body.
enum DeviceBodyFinish: String, Codable, CaseIterable, Identifiable {
    case matte
    case glossy

    var id: String { rawValue }
    var label: String {
        switch self {
        case .matte: "Matte"
        case .glossy: "Glossy"
        }
    }
}

/// Per-shape body-material configuration for 3D device frames.
/// All fields are optional; missing values fall back to the matte defaults that
/// shipped before this struct existed, so older projects render unchanged.
struct DeviceBodyMaterial: Codable, Equatable {
    static let defaultFinish: DeviceBodyFinish = .matte
    static let defaultMetalness: Double = 0.0
    static let defaultRoughness: Double = 0.4

    static let metalnessRange: ClosedRange<Double> = 0...1
    static let roughnessRange: ClosedRange<Double> = 0...1

    var finish: DeviceBodyFinish?
    var metalness: Double?
    var roughness: Double?

    enum CodingKeys: String, CodingKey {
        case finish = "fn"
        case metalness = "mt"
        case roughness = "rg"
    }

    init(finish: DeviceBodyFinish? = nil, metalness: Double? = nil, roughness: Double? = nil) {
        self.finish = finish
        self.metalness = metalness
        self.roughness = roughness
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finish = try c.decodeIfPresent(DeviceBodyFinish.self, forKey: .finish)
        metalness = try c.decodeIfPresent(Double.self, forKey: .metalness)
        roughness = try c.decodeIfPresent(Double.self, forKey: .roughness)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(finish, forKey: .finish)
        try c.encodeIfPresent(metalness, forKey: .metalness)
        try c.encodeIfPresent(roughness, forKey: .roughness)
    }

    var isEmpty: Bool { finish == nil && metalness == nil && roughness == nil }

    var resolvedFinish: DeviceBodyFinish { finish ?? Self.defaultFinish }
    var resolvedMetalness: Double { metalness ?? Self.defaultMetalness }
    var resolvedRoughness: Double { roughness ?? Self.defaultRoughness }
}
