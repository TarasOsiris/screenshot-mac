import SwiftUI

struct CanvasShapeView: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let isSelected: Bool
    var onSelect: () -> Void
    var onUpdate: (CanvasShapeModel) -> Void
    var onDelete: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var resizeDelta: ResizeDelta = .zero

    private var effectiveX: CGFloat { shape.x + dragOffset.width + resizeDelta.dx }
    private var effectiveY: CGFloat { shape.y + dragOffset.height + resizeDelta.dy }
    private var effectiveW: CGFloat { max(20, shape.width + resizeDelta.dw) }
    private var effectiveH: CGFloat { max(20, shape.height + resizeDelta.dh) }

    private var displayX: CGFloat { effectiveX * displayScale }
    private var displayY: CGFloat { effectiveY * displayScale }
    private var displayW: CGFloat { effectiveW * displayScale }
    private var displayH: CGFloat { effectiveH * displayScale }

    var body: some View {
        ZStack {
            shapeContent
                .frame(width: displayW, height: displayH)
                .opacity(shape.opacity)
                .rotationEffect(.degrees(shape.rotation))
        }
        .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
        .overlay {
            if isSelected {
                selectionOverlay
                resizeHandles
            }
        }
        .gesture(dragGesture)
        .onTapGesture { onSelect() }
    }

    @ViewBuilder
    private var shapeContent: some View {
        switch shape.type {
        case .rectangle:
            RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
                .fill(shape.color)

        case .circle:
            Ellipse()
                .fill(shape.color)

        case .text:
            Text(shape.text ?? "")
                .font(.system(
                    size: (shape.fontSize ?? 72) * displayScale,
                    weight: fontWeight(shape.fontWeight ?? 700)
                ))
                .foregroundStyle(shape.color)
                .multilineTextAlignment(shape.textAlign.textAlignment)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .image:
            RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
                .fill(shape.color.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24 * displayScale))
                        .foregroundStyle(.secondary)
                }

        case .device:
            DeviceFrameView(
                category: shape.deviceCategory ?? .iphone,
                bodyColor: shape.deviceBodyColor,
                width: displayW,
                height: displayH
            )
        }
    }

    private var selectionOverlay: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(shape.rotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
    }

    // MARK: - Resize Handles

    private var resizeHandles: some View {
        let cx = displayX + displayW / 2
        let cy = displayY + displayH / 2

        return ZStack {
            // Corners
            resizeHandle(at: CGPoint(x: displayX, y: displayY), edge: .topLeft)
            resizeHandle(at: CGPoint(x: displayX + displayW, y: displayY), edge: .topRight)
            resizeHandle(at: CGPoint(x: displayX, y: displayY + displayH), edge: .bottomLeft)
            resizeHandle(at: CGPoint(x: displayX + displayW, y: displayY + displayH), edge: .bottomRight)

            // Edges
            resizeHandle(at: CGPoint(x: cx, y: displayY), edge: .top)
            resizeHandle(at: CGPoint(x: cx, y: displayY + displayH), edge: .bottom)
            resizeHandle(at: CGPoint(x: displayX, y: cy), edge: .left)
            resizeHandle(at: CGPoint(x: displayX + displayW, y: cy), edge: .right)
        }
    }

    private func resizeHandle(at point: CGPoint, edge: ResizeEdge) -> some View {
        let handleSize: CGFloat = 8
        return Circle()
            .fill(Color.white)
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: handleSize, height: handleSize)
            .position(point)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let tx = value.translation.width / displayScale
                        let ty = value.translation.height / displayScale
                        resizeDelta = edge.delta(tx: tx, ty: ty, shapeWidth: shape.width, shapeHeight: shape.height)
                    }
                    .onEnded { _ in
                        var updated = shape
                        updated.x = effectiveX
                        updated.y = effectiveY
                        updated.width = effectiveW
                        updated.height = effectiveH
                        resizeDelta = .zero
                        onUpdate(updated)
                    }
            )
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onSelect()
                }
                dragOffset = CGSize(
                    width: value.translation.width / displayScale,
                    height: value.translation.height / displayScale
                )
            }
            .onEnded { _ in
                var updated = shape
                updated.x += dragOffset.width
                updated.y += dragOffset.height
                dragOffset = .zero
                isDragging = false
                onUpdate(updated)
            }
    }

    private func fontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case ...299: .light
        case 300...399: .regular
        case 400...599: .medium
        case 600...699: .semibold
        case 700...799: .bold
        default: .heavy
        }
    }
}

// MARK: - Resize Types

private struct ResizeDelta {
    var dx: CGFloat = 0
    var dy: CGFloat = 0
    var dw: CGFloat = 0
    var dh: CGFloat = 0

    static let zero = ResizeDelta()
}

private enum ResizeEdge {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    func delta(tx: CGFloat, ty: CGFloat, shapeWidth: CGFloat, shapeHeight: CGFloat) -> ResizeDelta {
        let minSize: CGFloat = 20
        switch self {
        case .topLeft:
            let dw = clampShrink(-tx, current: shapeWidth, min: minSize)
            let dh = clampShrink(-ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dx: -dw, dy: -dh, dw: dw, dh: dh)
        case .top:
            let dh = clampShrink(-ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dy: -dh, dh: dh)
        case .topRight:
            let dw = clampGrow(tx, current: shapeWidth, min: minSize)
            let dh = clampShrink(-ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dy: -dh, dw: dw, dh: dh)
        case .left:
            let dw = clampShrink(-tx, current: shapeWidth, min: minSize)
            return ResizeDelta(dx: -dw, dw: dw)
        case .right:
            let dw = clampGrow(tx, current: shapeWidth, min: minSize)
            return ResizeDelta(dw: dw)
        case .bottomLeft:
            let dw = clampShrink(-tx, current: shapeWidth, min: minSize)
            let dh = clampGrow(ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dx: -dw, dw: dw, dh: dh)
        case .bottom:
            let dh = clampGrow(ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dh: dh)
        case .bottomRight:
            let dw = clampGrow(tx, current: shapeWidth, min: minSize)
            let dh = clampGrow(ty, current: shapeHeight, min: minSize)
            return ResizeDelta(dw: dw, dh: dh)
        }
    }

    private func clampGrow(_ delta: CGFloat, current: CGFloat, min minSize: CGFloat) -> CGFloat {
        max(delta, minSize - current)
    }

    private func clampShrink(_ delta: CGFloat, current: CGFloat, min minSize: CGFloat) -> CGFloat {
        min(delta, current - minSize)
    }
}
