import Foundation
import SwiftUI

struct ScreenshotTemplate: Identifiable, Codable, BackgroundFillable {
    let id: UUID
    var backgroundColor: CodableColor
    var overrideBackground: Bool
    var backgroundStyle: BackgroundStyle
    var gradientConfig: GradientConfig
    var backgroundImageConfig: BackgroundImageConfig
    var backgroundBlur: Double

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = CodableColor(backgroundColor)
        self.overrideBackground = false
        self.backgroundStyle = .color
        self.gradientConfig = GradientConfig()
        self.backgroundImageConfig = BackgroundImageConfig()
        self.backgroundBlur = 0
    }

    enum CodingKeys: String, CodingKey {
        case id, backgroundColor = "bgc", overrideBackground = "ob"
        case backgroundStyle = "bgs", gradientConfig = "gc", backgroundImageConfig = "bgic"
        case backgroundBlur = "bgbl"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        backgroundColor = try c.decode(CodableColor.self, forKey: .backgroundColor)
        overrideBackground = try c.decodeIfPresent(Bool.self, forKey: .overrideBackground) ?? false
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .color
        gradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .gradientConfig) ?? GradientConfig()
        backgroundImageConfig = try c.decodeIfPresent(BackgroundImageConfig.self, forKey: .backgroundImageConfig) ?? BackgroundImageConfig()
        backgroundBlur = try c.decodeIfPresent(Double.self, forKey: .backgroundBlur) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(backgroundColor, forKey: .backgroundColor)
        if overrideBackground {
            try c.encode(true, forKey: .overrideBackground)
            if backgroundStyle != .color { try c.encode(backgroundStyle, forKey: .backgroundStyle) }
            if backgroundStyle == .gradient { try c.encode(gradientConfig, forKey: .gradientConfig) }
            if backgroundStyle == .image { try c.encode(backgroundImageConfig, forKey: .backgroundImageConfig) }
            if backgroundBlur != 0 { try c.encode(backgroundBlur, forKey: .backgroundBlur) }
        }
    }

    var bgColor: Color {
        get { backgroundColor.color }
        set { backgroundColor = CodableColor(newValue) }
    }

    func duplicated() -> ScreenshotTemplate {
        var copy = ScreenshotTemplate(id: UUID(), backgroundColor: bgColor)
        copy.overrideBackground = overrideBackground
        copy.backgroundStyle = backgroundStyle
        copy.gradientConfig = gradientConfig
        copy.backgroundImageConfig = backgroundImageConfig
        copy.backgroundBlur = backgroundBlur
        return copy
    }
}
