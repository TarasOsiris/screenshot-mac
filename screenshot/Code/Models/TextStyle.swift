import Foundation
import SwiftUI

enum TextAlign: String, Codable {
    case left
    case center
    case right
}

enum TextVerticalAlign: String, Codable {
    case top
    case center
    case bottom
}

struct TextStyle {
    var fontName: String?
    var fontSize: CGFloat?
    var fontWeight: Int?
    var textAlign: TextAlign?
    var textVerticalAlign: TextVerticalAlign?
    var italic: Bool?
    var uppercase: Bool?
    var letterSpacing: CGFloat?
    var lineSpacing: CGFloat?
    var lineHeightMultiple: CGFloat?
    var colorData: CodableColor
    var opacity: Double
}

extension Optional where Wrapped == TextAlign {
    var textAlignment: TextAlignment {
        switch self {
        case .left: .leading
        case .right: .trailing
        default: .center
        }
    }
}

extension CanvasShapeModel {
    var resolvedFrameAlignment: Alignment {
        let h: HorizontalAlignment = switch textAlign {
        case .left: .leading
        case .right: .trailing
        default: .center
        }
        let v: VerticalAlignment = switch textVerticalAlign {
        case .top: .top
        case .bottom: .bottom
        default: .center
        }
        return Alignment(horizontal: h, vertical: v)
    }
}
