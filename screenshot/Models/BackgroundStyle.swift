import SwiftUI

enum BackgroundStyle: String, Codable, CaseIterable {
    case color
    case gradient
}

struct GradientConfig: Codable, Equatable {
    var color1Data: CodableColor
    var color2Data: CodableColor
    var angle: Double // degrees

    init(color1: Color = Color(red: 0.4, green: 0.49, blue: 0.92),
         color2: Color = Color(red: 0.46, green: 0.29, blue: 0.64),
         angle: Double = 135) {
        self.color1Data = CodableColor(color1)
        self.color2Data = CodableColor(color2)
        self.angle = angle
    }

    var color1: Color {
        get { color1Data.color }
        set { color1Data = CodableColor(newValue) }
    }

    var color2: Color {
        get { color2Data.color }
        set { color2Data = CodableColor(newValue) }
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
        LinearGradient(colors: [color1, color2], startPoint: startPoint, endPoint: endPoint)
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
]
