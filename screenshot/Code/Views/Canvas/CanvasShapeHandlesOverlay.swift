import SwiftUI

struct CanvasShapeHandlesOverlay: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let zoom: CGFloat
    let displayX: CGFloat
    let displayY: CGFloat
    let displayW: CGFloat
    let displayH: CGFloat
    let currentRotation: Double
    let handleDiameter: CGFloat
    @Binding var rotationDelta: Double
    @Binding var resizeState: ResizeState?
    let onUpdate: (CanvasShapeModel) -> Void

    var body: some View {
        selectionOverlay
        resizeHandles
    }

    private var rotationRadians: CGFloat { shape.rotation * .pi / 180 }

    private var selectionOverlay: some View {
        Rectangle()
            .strokeBorder(Color.accentColor.opacity(1.0), lineWidth: 1.5 / zoom)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(currentRotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
            .allowsHitTesting(false)
    }

    private var resizeHandles: some View {
        ZStack {
            resizeHandle(edge: .topLeft)
            resizeHandle(edge: .topRight)
            resizeHandle(edge: .bottomLeft)
            resizeHandle(edge: .bottomRight)
            resizeHandle(edge: .top)
            resizeHandle(edge: .bottom)
            resizeHandle(edge: .left)
            resizeHandle(edge: .right)
            rotateHandleContent
        }
        .frame(width: displayW, height: displayH)
        .rotationEffect(.degrees(currentRotation))
        .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
    }

    private var rotateHandleContent: some View {
        let stemLength: CGFloat = 24 / zoom
        let handleSize: CGFloat = 10 / zoom
        let hitSize: CGFloat = 24 / zoom

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: displayW / 2, y: -handleDiameter / (2 * zoom)))
                path.addLine(to: CGPoint(x: displayW / 2, y: -stemLength))
            }
            .stroke(Color.accentColor, lineWidth: 1 / zoom)

            ZStack {
                Color.clear
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())

                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)

                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom)
                    .frame(width: handleSize, height: handleSize)
            }
            .onHover { hovering in
                if hovering {
                    CursorHelper.rotateCursor.push()
                } else {
                    NSCursor.pop()
                }
            }
            .position(x: displayW / 2, y: -stemLength)
            .gesture(rotateGesture(stemLength: stemLength))
        }
    }

    private func rotateGesture(stemLength: CGFloat) -> some Gesture {
        let handleDistance = (displayH / 2 + stemLength) * zoom
        let baseAngleRadians = (shape.rotation - 90) * .pi / 180
        let handleVectorX = handleDistance * cos(baseAngleRadians)
        let handleVectorY = handleDistance * sin(baseAngleRadians)
        let startAngle = atan2(handleVectorY, handleVectorX) * 180 / .pi

        return DragGesture(coordinateSpace: .global)
            .onChanged { value in
                CursorHelper.rotateCursor.set()

                let currentX = handleVectorX + value.translation.width
                let currentY = handleVectorY + value.translation.height
                let currentAngle = atan2(currentY, currentX) * 180 / .pi

                var delta = currentAngle - startAngle
                if NSEvent.modifierFlags.contains(.shift) {
                    let target = shape.rotation + delta
                    let snapped = (target / 15).rounded() * 15
                    delta = snapped - shape.rotation
                }

                rotationDelta = delta
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                var updated = shape
                updated.rotation = normalizeAngle(shape.rotation + rotationDelta)
                rotationDelta = 0
                onUpdate(updated)
            }
    }

    private func normalizeAngle(_ angle: Double) -> Double {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private func handlePosition(for edge: ResizeEdge) -> CGPoint {
        let halfWidth = displayW / 2
        let halfHeight = displayH / 2
        switch edge {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: halfWidth, y: 0)
        case .topRight: return CGPoint(x: displayW, y: 0)
        case .left: return CGPoint(x: 0, y: halfHeight)
        case .right: return CGPoint(x: displayW, y: halfHeight)
        case .bottomLeft: return CGPoint(x: 0, y: displayH)
        case .bottom: return CGPoint(x: halfWidth, y: displayH)
        case .bottomRight: return CGPoint(x: displayW, y: displayH)
        }
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        let handleSize = handleDiameter / zoom
        let hitSize: CGFloat = 20 / zoom
        let position = handlePosition(for: edge)

        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())

            Circle()
                .fill(Color.white)
                .strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom)
                .frame(width: handleSize, height: handleSize)
                .allowsHitTesting(false)
        }
        .onHover { hovering in
            if hovering {
                CursorHelper.resizeCursor(for: edge, rotation: currentRotation).push()
            } else {
                NSCursor.pop()
            }
        }
        .position(position)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let effectiveScale = displayScale * zoom
                    let tx = value.translation.width / effectiveScale
                    let ty = value.translation.height / effectiveScale
                    let lockAspectRatio = NSEvent.modifierFlags.contains(.shift) || (shape.type == .device && (shape.deviceFrameId != nil || shape.deviceCategory != .invisible))
                    resizeState = computeResize(edge: edge, tx: tx, ty: ty, lockAspectRatio: lockAspectRatio)
                }
                .onEnded { _ in
                    if let resizeState {
                        var updated = shape
                        updated.x = resizeState.newX
                        updated.y = resizeState.newY
                        updated.width = resizeState.newW
                        updated.height = resizeState.newH
                        onUpdate(updated)
                    }
                    resizeState = nil
                }
        )
    }

    private func computeResize(edge: ResizeEdge, tx: CGFloat, ty: CGFloat, lockAspectRatio: Bool) -> ResizeState {
        let minSize: CGFloat = shape.type == .device ? CanvasShapeModel.deviceMinSize : 20
        let cosA = cos(rotationRadians)
        let sinA = sin(rotationRadians)
        let localTx = tx * cosA + ty * sinA
        let localTy = -tx * sinA + ty * cosA

        var newW = shape.width
        var newH = shape.height
        switch edge {
        case .topLeft:
            newW = max(minSize, shape.width - localTx)
            newH = max(minSize, shape.height - localTy)
        case .top:
            newH = max(minSize, shape.height - localTy)
        case .topRight:
            newW = max(minSize, shape.width + localTx)
            newH = max(minSize, shape.height - localTy)
        case .left:
            newW = max(minSize, shape.width - localTx)
        case .right:
            newW = max(minSize, shape.width + localTx)
        case .bottomLeft:
            newW = max(minSize, shape.width - localTx)
            newH = max(minSize, shape.height + localTy)
        case .bottom:
            newH = max(minSize, shape.height + localTy)
        case .bottomRight:
            newW = max(minSize, shape.width + localTx)
            newH = max(minSize, shape.height + localTy)
        }

        if lockAspectRatio {
            let baseW = max(shape.width, 1)
            let baseH = max(shape.height, 1)
            let minScale = max(minSize / baseW, minSize / baseH)

            let widthScale = newW / baseW
            let heightScale = newH / baseH

            let scale: CGFloat
            switch edge {
            case .left, .right:
                scale = max(minScale, widthScale)
            case .top, .bottom:
                scale = max(minScale, heightScale)
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                let useWidth = abs(widthScale - 1) >= abs(heightScale - 1)
                scale = max(minScale, useWidth ? widthScale : heightScale)
            }

            newW = baseW * scale
            newH = baseH * scale
        }

        let anchor = edge.anchorPoint(width: shape.width, height: shape.height)
        let centerX = shape.x + shape.width / 2
        let centerY = shape.y + shape.height / 2
        let anchorX = anchor.x - shape.width / 2
        let anchorY = anchor.y - shape.height / 2
        let anchorCanvasX = centerX + anchorX * cosA - anchorY * sinA
        let anchorCanvasY = centerY + anchorX * sinA + anchorY * cosA

        let newAnchor = edge.anchorPoint(width: newW, height: newH)
        let newAnchorX = newAnchor.x - newW / 2
        let newAnchorY = newAnchor.y - newH / 2
        let newCenterX = anchorCanvasX - (newAnchorX * cosA - newAnchorY * sinA)
        let newCenterY = anchorCanvasY - (newAnchorX * sinA + newAnchorY * cosA)

        return ResizeState(
            newX: newCenterX - newW / 2,
            newY: newCenterY - newH / 2,
            newW: newW,
            newH: newH
        )
    }
}
