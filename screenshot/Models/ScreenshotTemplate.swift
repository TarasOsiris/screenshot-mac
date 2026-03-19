import Foundation
import SwiftUI

struct ScreenshotTemplate: Identifiable, Codable, BackgroundFillable {
    let id: UUID
    var backgroundColor: CodableColor
    var overrideBackground: Bool
    var backgroundStyle: BackgroundStyle
    var gradientConfig: GradientConfig
    var backgroundImageConfig: BackgroundImageConfig

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = CodableColor(backgroundColor)
        self.overrideBackground = false
        self.backgroundStyle = .color
        self.gradientConfig = GradientConfig()
        self.backgroundImageConfig = BackgroundImageConfig()
    }

    enum CodingKeys: String, CodingKey {
        case id, backgroundColor = "bgc", overrideBackground = "ob"
        case backgroundStyle = "bgs", gradientConfig = "gc", backgroundImageConfig = "bgic"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.flexContainer()
        id = try c.decode(UUID.self, "id")
        backgroundColor = try c.decode(CodableColor.self, "bgc", "backgroundColor")
        overrideBackground = try c.opt(Bool.self, "ob", "overrideBackground") ?? false
        backgroundStyle = try c.opt(BackgroundStyle.self, "bgs", "backgroundStyle") ?? .color
        gradientConfig = try c.opt(GradientConfig.self, "gc", "gradientConfig") ?? GradientConfig()
        backgroundImageConfig = try c.opt(BackgroundImageConfig.self, "bgic", "backgroundImageConfig") ?? BackgroundImageConfig()
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
        return copy
    }
}
