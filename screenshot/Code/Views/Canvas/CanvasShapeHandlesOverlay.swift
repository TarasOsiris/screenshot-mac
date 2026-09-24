import SwiftUI

struct CanvasShapeHandlesOverlay: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let zoom: CGFloat
    let displayRect: CGRect
    let currentRotation: Double
    let handleDiameter: CGFloat
    @Binding var rotationDelta: Double
    @Binding var resizeState: ResizeState?
    /// Holds the gesture's pre-resize base — see `CanvasDragSession.resizeBase` — and its snap
    /// state. Only written here, never read in `body`, so this registers no per-tick dependency.
    let dragSession: CanvasDragSession
    /// Turns a handle's model-space translation into the frame to show, snapping included.
    let resolveResize: (_ base: CanvasShapeModel, _ edge: ResizeEdge, _ translation: CGSize, _ lockAspectRatio: Bool) -> ResizeState
    let onResizeEnded: () -> Void
    let onUpdate: (CanvasShapeModel) -> Void

    /// Only `CanvasSelectionLayer` builds this, and only for a single selection — see the
    /// rationale for handle-free multi-selection chrome there.
    var body: some View {
        ShapeSelectionOutline(
            isLocked: shape.resolvedIsLocked,
            displayRect: displayRect,
            rotation: currentRotation,
            zoom: zoom
        )
        if !shape.resolvedIsLocked {
            resizeHandles
        }
    }

    private var displayX: CGFloat { displayRect.minX }
    private var displayY: CGFloat { displayRect.minY }
    private var displayW: CGFloat { displayRect.width }
    private var displayH: CGFloat { displayRect.height }

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
            .cursorHover(.rotate, for: .rotateHandle)
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

        return DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                PlatformCursor.hold(.rotate, for: .rotateHandle)

                let currentX = handleVectorX + value.translation.width
                let currentY = handleVectorY + value.translation.height
                let currentAngle = atan2(currentY, currentX) * 180 / .pi

                var delta = currentAngle - startAngle
                if PlatformModifiers.shiftDown {
                    let target = shape.rotation + delta
                    let snapped = (target / 15).rounded() * 15
                    delta = snapped - shape.rotation
                }

                rotationDelta = delta
            }
            .onEnded { _ in
                PlatformCursor.release(.rotateHandle)
                let delta = rotationDelta
                // Cleared before the commit, unlike the resize handle: `pendingRotation` is a
                // delta the canvas *adds* to `shape.rotation`, where `ResizeState` is absolute.
                rotationDelta = 0
                // `minimumDistance: 0` reports a bare click as a zero-delta gesture; committing it
                // would walk the whole undo/save machinery to discover there is nothing to record.
                guard delta != 0 else { return }
                var updated = shape
                updated.rotation = shape.rotation + delta
                onUpdate(updated)
            }
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
        .cursorHover(resizeCursor(for: edge), for: .resizeHandle(edge))
        .position(position)
        .gesture(
            // `minimumDistance: 0` — the default 10 pt threshold isn't a dead zone; the first
            // tick reports it as translation, so the shape jumps by it before tracking starts.
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    PlatformCursor.hold(resizeCursor(for: edge), for: .resizeHandle(edge))
                    // `resizeState == nil` is the authoritative "gesture began" — it is the
                    // binding this gesture itself fills. The zero-translation test stays as the
                    // second signal, for a fresh gesture following one whose `onEnded` never came.
                    if resizeState == nil || value.translation == .zero {
                        dragSession.resizeBase[shape.id] = shape
                        dragSession.endSnapping()
                    }
                    let base = dragSession.resizeBase[shape.id] ?? shape
                    let effectiveScale = displayScale * zoom
                    resizeState = resolveResize(
                        base,
                        edge,
                        CGSize(
                            width: value.translation.width / effectiveScale,
                            height: value.translation.height / effectiveScale
                        ),
                        PlatformModifiers.shiftDown || base.locksAspectRatioOnResize
                    )
                }
                .onEnded { _ in
                    PlatformCursor.release(.resizeHandle(edge))
                    if let resizeState, resizeState.movedFrom(shape) {
                        var updated = shape
                        updated.x = resizeState.newX
                        updated.y = resizeState.newY
                        updated.width = resizeState.newW
                        updated.height = resizeState.newH
                        onUpdate(updated)
                    }
                    dragSession.resizeBase[shape.id] = nil
                    resizeState = nil
                    onResizeEnded()
                }
        )
    }

    private func resizeCursor(for edge: ResizeEdge) -> PlatformCursor.Kind {
        .resize(edge: edge, rotation: currentRotation)
    }
}
