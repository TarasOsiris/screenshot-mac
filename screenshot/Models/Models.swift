import Foundation
import SwiftUI

struct Project: Identifiable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct ScreenshotTemplate: Identifiable {
    let id: UUID
    var backgroundColor: Color

    init(id: UUID = UUID(), backgroundColor: Color = .blue) {
        self.id = id
        self.backgroundColor = backgroundColor
    }
}

struct ScreenshotRow: Identifiable {
    let id: UUID
    var label: String
    var templates: [ScreenshotTemplate]
    var templateWidth: CGFloat
    var templateHeight: CGFloat

    init(
        id: UUID = UUID(),
        label: String = "Screenshot 1",
        templates: [ScreenshotTemplate] = [],
        templateWidth: CGFloat = 1290,
        templateHeight: CGFloat = 2796
    ) {
        self.id = id
        self.label = label
        self.templates = templates
        self.templateWidth = templateWidth
        self.templateHeight = templateHeight
    }

    var displayScale: CGFloat {
        let maxDisplayHeight: CGFloat = 500
        return min(1, maxDisplayHeight / templateHeight)
    }

    var displayWidth: CGFloat {
        templateWidth * displayScale
    }

    var displayHeight: CGFloat {
        templateHeight * displayScale
    }

    var resolutionLabel: String {
        "\(Int(templateWidth))x\(Int(templateHeight))"
    }
}
