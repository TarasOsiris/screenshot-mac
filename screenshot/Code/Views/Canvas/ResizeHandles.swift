import SwiftUI

struct ResizeState {
    var newX: CGFloat
    var newY: CGFloat
    var newW: CGFloat
    var newH: CGFloat
}

enum ResizeEdge {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    /// The point that should stay fixed (opposite corner/edge), in local shape coords (0,0 = top-left)
    func anchorPoint(width w: CGFloat, height h: CGFloat) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: w, y: h)
        case .top:         return CGPoint(x: w / 2, y: h)
        case .topRight:    return CGPoint(x: 0, y: h)
        case .left:        return CGPoint(x: w, y: h / 2)
        case .right:       return CGPoint(x: 0, y: h / 2)
        case .bottomLeft:  return CGPoint(x: w, y: 0)
        case .bottom:      return CGPoint(x: w / 2, y: 0)
        case .bottomRight: return CGPoint(x: 0, y: 0)
        }
    }
}
