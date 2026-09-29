import Foundation
import SwiftUI

nonisolated enum ShapeType: String, Codable, CaseIterable {
    case rectangle
    case circle
    case star
    case text
    case image
    case device
    case svg

    var icon: String {
        switch self {
        case .rectangle: "rectangle.fill"
        case .circle: "circle.fill"
        case .star: "star.fill"
        case .text: "textformat"
        case .image: "photo"
        case .device: "iphone"
        case .svg: "chevron.left.forwardslash.chevron.right"
        }
    }

    var label: String {
        switch self {
        case .rectangle: String(localized: "Rectangle")
        case .circle: String(localized: "Circle")
        case .star: String(localized: "Star")
        case .text: String(localized: "Text")
        case .image: String(localized: "Image")
        case .device: String(localized: "Device")
        case .svg: String(localized: "SVG")
        }
    }

    var pluralLabel: String {
        switch self {
        case .rectangle: String(localized: "Rectangles")
        case .circle: String(localized: "Circles")
        case .star: String(localized: "Stars")
        case .text: String(localized: "Text")
        case .image: String(localized: "Images")
        case .device: String(localized: "Devices")
        case .svg: String(localized: "SVGs")
        }
    }

    /// Shape types grouped under the "Shapes" menu in the toolbar.
    static let shapeMenuTypes: [ShapeType] = [.rectangle, .circle, .star]

    /// Text's outline strokes the glyphs rather than a box edge.
    var supportsOutline: Bool {
        switch self {
        case .rectangle, .circle, .star, .image, .text: true
        case .device, .svg: false
        }
    }

    /// Text's fill paints the glyphs, with a color or a gradient.
    var supportsFill: Bool {
        switch self {
        case .rectangle, .circle, .star, .text: true
        case .image, .device, .svg: false
        }
    }

    /// Whether the fill may be an image; text glyphs can't take one.
    var supportsFillImage: Bool { supportsFill && self != .text }
}
