import Foundation
import SwiftUI

extension CanvasShapeModel {
    static func defaultRectangle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .rectangle, x: centerX - 250, y: centerY - 200, width: 500, height: 400, color: .orange)
    }

    static func defaultCircle(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .circle, x: centerX - 200, y: centerY - 200, width: 400, height: 400, color: .purple)
    }

    static func defaultStar(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .star, x: centerX - 200, y: centerY - 200, width: 400, height: 400, color: .yellow, starPointCount: defaultStarPointCount)
    }

    static func defaultText(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        let text = String(localized: "Your awesome new feature here!")
        let fontSize: CGFloat = 110
        let fontWeight: Int = 700
        let width: CGFloat = 700
        let nsFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let boundingRect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: nsFont],
            context: nil
        )
        let height = ceil(boundingRect.height) + fontSize * 0.2
        return CanvasShapeModel(
            type: .text, x: centerX - width / 2, y: centerY - height / 2, width: width, height: height,
            color: .white, text: text, fontSize: fontSize, fontWeight: fontWeight, textAlign: .center
        )
    }

    static func defaultImage(centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        CanvasShapeModel(type: .image, x: centerX - 250, y: centerY - 250, width: 500, height: 500, color: .gray)
    }

    static func defaultSvg(centerX: CGFloat, centerY: CGFloat, svgContent: String, size: CGSize) -> CanvasShapeModel {
        CanvasShapeModel(
            type: .svg, x: centerX - size.width / 2, y: centerY - size.height / 2,
            width: size.width, height: size.height,
            color: .white, svgContent: svgContent, svgUseColor: false
        )
    }

    /// Creates a default shape for the given type, placed at the specified center.
    /// Returns `nil` for `.svg` which requires additional parameters.
    static func defaultShape(for type: ShapeType, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel? {
        switch type {
        case .rectangle: return defaultRectangle(centerX: centerX, centerY: centerY)
        case .circle: return defaultCircle(centerX: centerX, centerY: centerY)
        case .star: return defaultStar(centerX: centerX, centerY: centerY)
        case .text: return defaultText(centerX: centerX, centerY: centerY)
        case .image: return defaultImage(centerX: centerX, centerY: centerY)
        case .device: return defaultDeviceFromRow(row, centerX: centerX, centerY: centerY)
        case .svg: return nil
        }
    }
}
