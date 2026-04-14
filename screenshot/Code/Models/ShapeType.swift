import Foundation
import SwiftUI

enum ShapeType: String, Codable, CaseIterable {
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
        case .rectangle: "Rectangle"
        case .circle: "Circle"
        case .star: "Star"
        case .text: "Text"
        case .image: "Image"
        case .device: "Device"
        case .svg: "SVG"
        }
    }

    var pluralLabel: String {
        switch self {
        case .text: "Text"
        default: label + "s"
        }
    }

    /// Shape types grouped under the "Shapes" menu in the toolbar.
    static let shapeMenuTypes: [ShapeType] = [.rectangle, .circle, .star]

    var supportsOutline: Bool {
        switch self {
        case .rectangle, .circle, .star: true
        case .text, .image, .device, .svg: false
        }
    }

    var supportsFill: Bool { supportsOutline }
}
