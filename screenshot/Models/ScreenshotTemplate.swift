import Foundation
import SwiftUI

struct ScreenshotTemplate: Identifiable, Codable, BackgroundFillable {
    let id: UUID
    var backgroundColor: CodableColor
    var overrideBackground: Bool
    var backgroundStyle: BackgroundStyle
    var gradientConfig: GradientConfig

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = CodableColor(backgroundColor)
        self.overrideBackground = false
        self.backgroundStyle = .color
        self.gradientConfig = GradientConfig()
    }

    enum CodingKeys: String, CodingKey {
        case id, backgroundColor, overrideBackground, backgroundStyle, gradientConfig
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        backgroundColor = try c.decode(CodableColor.self, forKey: .backgroundColor)
        overrideBackground = try c.decodeIfPresent(Bool.self, forKey: .overrideBackground) ?? false
        backgroundStyle = try c.decodeIfPresent(BackgroundStyle.self, forKey: .backgroundStyle) ?? .color
        gradientConfig = try c.decodeIfPresent(GradientConfig.self, forKey: .gradientConfig) ?? GradientConfig()
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
        return copy
    }
}
