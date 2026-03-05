import Foundation
import SwiftUI

enum DeviceCategory: String, CaseIterable, Identifiable {
    case iphone = "iPhone"
    case ipad = "iPad"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .iphone: "iphone"
        case .ipad: "ipad"
        }
    }
}

struct DevicePreset: Identifiable {
    let id = UUID()
    let name: String
    let width: CGFloat
    let height: CGFloat
    let category: DeviceCategory
}

let devicePresets: [DevicePreset] = [
    DevicePreset(name: "iPhone 6.7\"", width: 1290, height: 2796, category: .iphone),
    DevicePreset(name: "iPhone 6.5\"", width: 1284, height: 2778, category: .iphone),
    DevicePreset(name: "iPhone 5.5\"", width: 1242, height: 2208, category: .iphone),
    DevicePreset(name: "iPad 12.9\"", width: 2048, height: 2732, category: .ipad),
    DevicePreset(name: "iPad 11\"", width: 1668, height: 2388, category: .ipad),
]

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
    var bgColor: Color
    var showDevice: Bool

    init(
        id: UUID = UUID(),
        label: String = "Screenshot 1",
        templates: [ScreenshotTemplate] = [],
        templateWidth: CGFloat = 1290,
        templateHeight: CGFloat = 2796,
        bgColor: Color = .blue,
        showDevice: Bool = true
    ) {
        self.id = id
        self.label = label
        self.templates = templates
        self.templateWidth = templateWidth
        self.templateHeight = templateHeight
        self.bgColor = bgColor
        self.showDevice = showDevice
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
