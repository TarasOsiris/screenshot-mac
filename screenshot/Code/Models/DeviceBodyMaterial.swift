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
struct DeviceBodyMaterial: Codable, Equatable {
    static let defaultFinish: DeviceBodyFinish = .glossy

    var finish: DeviceBodyFinish?

    enum CodingKeys: String, CodingKey {
        case finish = "fn"
    }

    init(finish: DeviceBodyFinish? = nil) {
        self.finish = finish
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        finish = try c.decodeIfPresent(DeviceBodyFinish.self, forKey: .finish)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(finish, forKey: .finish)
    }

    var isEmpty: Bool { finish == nil }

    var resolvedFinish: DeviceBodyFinish { finish ?? Self.defaultFinish }
    var resolvedMetalness: Double { resolvedFinish == .glossy ? 1.0 : 0.0 }
    var resolvedRoughness: Double { resolvedFinish == .glossy ? 0.0 : 1.0 }
}
