import SwiftUI

enum BackgroundStyle: String, Codable, CaseIterable {
    case color
    case gradient
}

struct GradientColorStop: Codable, Equatable, Identifiable {
    var id: UUID
    var colorData: CodableColor
    var location: Double // 0.0 to 1.0

    init(id: UUID = UUID(), color: Color, location: Double) {
        self.id = id
        self.colorData = CodableColor(color)
        self.location = min(max(location, 0), 1)
    }

    var color: Color {
        get { colorData.color }
        set { colorData = CodableColor(newValue) }
    }
}

struct GradientConfig: Codable, Equatable {
    var stops: [GradientColorStop]
    var angle: Double // degrees

    init(stops: [GradientColorStop], angle: Double = 135) {
        self.stops = stops.sorted { $0.location < $1.location }
        self.angle = angle
    }

    init(color1: Color = Color(red: 0.4, green: 0.49, blue: 0.92),
         color2: Color = Color(red: 0.46, green: 0.29, blue: 0.64),
         angle: Double = 135) {
        self.stops = [
            GradientColorStop(color: color1, location: 0),
            GradientColorStop(color: color2, location: 1),
        ]
        self.angle = angle
    }

    // Backward-compatible decoding
    enum CodingKeys: String, CodingKey {
        case stops, angle
        case color1Data, color2Data // legacy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        angle = try c.decode(Double.self, forKey: .angle)

        if let stops = try c.decodeIfPresent([GradientColorStop].self, forKey: .stops) {
            self.stops = stops.sorted { $0.location < $1.location }
        } else {
            // Migrate from old color1Data/color2Data format
            let c1 = try c.decode(CodableColor.self, forKey: .color1Data)
            let c2 = try c.decode(CodableColor.self, forKey: .color2Data)
            self.stops = [
                GradientColorStop(color: c1.color, location: 0),
                GradientColorStop(color: c2.color, location: 1),
            ]
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(stops, forKey: .stops)
        try c.encode(angle, forKey: .angle)
    }

    private var radians: Double {
        (angle - 90) * .pi / 180
    }

    var startPoint: UnitPoint {
        UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    var endPoint: UnitPoint {
        UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    var linearGradient: LinearGradient {
        let swiftUIStops = stops.map { Gradient.Stop(color: $0.color, location: $0.location) }
        return LinearGradient(
            stops: swiftUIStops,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    @discardableResult
    mutating func addStop(color: Color, at location: Double) -> UUID {
        let stop = GradientColorStop(color: color, location: location)
        stops.append(stop)
        stops.sort { $0.location < $1.location }
        return stop.id
    }

    mutating func removeStop(id: UUID) {
        guard stops.count > 2 else { return }
        stops.removeAll { $0.id == id }
    }

    mutating func reverseStops() {
        for i in stops.indices {
            stops[i].location = 1.0 - stops[i].location
        }
        stops.reverse()
    }
}

struct GradientPreset: Identifiable {
    let id = UUID()
    let label: String
    let config: GradientConfig

    init(label: String, color1: Color, color2: Color, angle: Double) {
        self.label = label
        self.config = GradientConfig(color1: color1, color2: color2, angle: angle)
    }

    init(label: String, stops: [GradientColorStop], angle: Double) {
        self.label = label
        self.config = GradientConfig(stops: stops, angle: angle)
    }
}

let gradientPresets: [GradientPreset] = [
    GradientPreset(label: "Ocean", color1: Color(red: 0.4, green: 0.49, blue: 0.92), color2: Color(red: 0.46, green: 0.29, blue: 0.64), angle: 135),
    GradientPreset(label: "Sunset", color1: Color(red: 0.94, green: 0.58, blue: 0.98), color2: Color(red: 0.96, green: 0.34, blue: 0.42), angle: 135),
    GradientPreset(label: "Peach", color1: Color(red: 0.96, green: 0.83, blue: 0.40), color2: Color(red: 0.99, green: 0.63, blue: 0.52), angle: 135),
    GradientPreset(label: "Mint", color1: Color(red: 0.63, green: 0.77, blue: 0.99), color2: Color(red: 0.76, green: 0.91, blue: 0.98), angle: 135),
    GradientPreset(label: "Berry", color1: Color(red: 0.63, green: 0.55, blue: 0.82), color2: Color(red: 0.98, green: 0.76, blue: 0.92), angle: 135),
    GradientPreset(label: "Flame", color1: Color(red: 0.97, green: 0.21, blue: 0.0), color2: Color(red: 0.98, green: 0.83, blue: 0.14), angle: 135),
    GradientPreset(label: "Sky", color1: Color(red: 0.54, green: 0.97, blue: 1.0), color2: Color(red: 0.40, green: 0.65, blue: 1.0), angle: 135),
    GradientPreset(label: "Forest", color1: Color(red: 0.07, green: 0.60, blue: 0.56), color2: Color(red: 0.22, green: 0.94, blue: 0.49), angle: 135),
    GradientPreset(label: "Night", color1: Color(red: 0.06, green: 0.13, blue: 0.15), color2: Color(red: 0.17, green: 0.33, blue: 0.39), angle: 135),
    GradientPreset(label: "Rose", color1: Color(red: 0.93, green: 0.61, blue: 0.65), color2: Color(red: 1.0, green: 0.87, blue: 0.88), angle: 135),
    GradientPreset(label: "Indigo", color1: Color(red: 0.26, green: 0.22, blue: 0.79), color2: Color(red: 0.39, green: 0.40, blue: 0.95), angle: 135),
    GradientPreset(label: "Emerald", color1: Color(red: 0.02, green: 0.59, blue: 0.41), color2: Color(red: 0.20, green: 0.83, blue: 0.60), angle: 135),
    // Multi-stop presets
    GradientPreset(label: "Rainbow", stops: [
        GradientColorStop(color: Color(red: 1, green: 0.2, blue: 0.2), location: 0),
        GradientColorStop(color: Color(red: 1, green: 0.8, blue: 0.2), location: 0.25),
        GradientColorStop(color: Color(red: 0.2, green: 0.9, blue: 0.4), location: 0.5),
        GradientColorStop(color: Color(red: 0.3, green: 0.5, blue: 1), location: 0.75),
        GradientColorStop(color: Color(red: 0.7, green: 0.3, blue: 0.9), location: 1),
    ], angle: 90),
    GradientPreset(label: "Aurora", stops: [
        GradientColorStop(color: Color(red: 0.05, green: 0.1, blue: 0.3), location: 0),
        GradientColorStop(color: Color(red: 0.1, green: 0.6, blue: 0.5), location: 0.4),
        GradientColorStop(color: Color(red: 0.4, green: 0.9, blue: 0.6), location: 0.7),
        GradientColorStop(color: Color(red: 0.9, green: 0.95, blue: 0.8), location: 1),
    ], angle: 0),
    GradientPreset(label: "Warm Sunset", stops: [
        GradientColorStop(color: Color(red: 0.15, green: 0.05, blue: 0.3), location: 0),
        GradientColorStop(color: Color(red: 0.8, green: 0.2, blue: 0.4), location: 0.4),
        GradientColorStop(color: Color(red: 1, green: 0.6, blue: 0.2), location: 0.75),
        GradientColorStop(color: Color(red: 1, green: 0.9, blue: 0.5), location: 1),
    ], angle: 0),
    GradientPreset(label: "Deep Sea", stops: [
        GradientColorStop(color: Color(red: 0.0, green: 0.05, blue: 0.15), location: 0),
        GradientColorStop(color: Color(red: 0.0, green: 0.2, blue: 0.5), location: 0.5),
        GradientColorStop(color: Color(red: 0.2, green: 0.7, blue: 0.8), location: 1),
    ], angle: 180),
]
