import SwiftUI

struct StarShape: InsettableShape {
    var pointCount: Int
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let points = max(pointCount, 3)
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let center = CGPoint(x: insetRect.midX, y: insetRect.midY)
        let outerRadius = min(insetRect.width, insetRect.height) / 2
        let innerRadius = outerRadius * 0.382 // golden ratio based inner radius

        var path = Path()
        let totalPoints = points * 2
        let angleIncrement = CGFloat.pi * 2 / CGFloat(totalPoints)
        let startAngle = -CGFloat.pi / 2 // start from top

        for i in 0..<totalPoints {
            let angle = startAngle + angleIncrement * CGFloat(i)
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> StarShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
