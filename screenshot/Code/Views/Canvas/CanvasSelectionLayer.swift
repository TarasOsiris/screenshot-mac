import SwiftUI

/// The single owner of selection chrome (outlines + resize/rotation handles)
/// for both single- and multi-select, and for the shapes an in-flight marquee
/// has swept up. Sits above the whole shape layer so handles always paint on
/// top and stay grabbable even when the shape is behind another — don't
/// reintroduce inline handles in `CanvasShapeView`, and don't draw an outline
/// from any other layer. Drawn at the canvas's full (zoom-inclusive)
/// `visualScale` so handle and outline thickness stay pixel-perfect at every
/// zoom level.
struct CanvasSelectionLayer: View {
    @Environment(\.displayScale) private var screenScale

    let row: ScreenshotRow
    /// Resolved shapes (with locale overrides applied) — shared with the
    /// row's shape layer so we don't repeat `LocaleService.resolveShapes` here.
    let resolvedShapes: [CanvasShapeModel]
    let selectedShapeIds: Set<UUID>
    /// Visual scale: model points × (base displayScale × zoom).
    let visualScale: CGFloat
    /// Read inside `body` on purpose: per-tick drag/resize updates re-render
    /// just this overlay, not the row that owns it.
    let dragSession: CanvasDragSession
    let textEditingShapeId: UUID?
    let onUpdate: (CanvasShapeModel) -> Void

    private let handleDiameter: CGFloat = 8

    var body: some View {
        // A sweep's set already contains the pre-drag selection it adds to, so it simply
        // replaces it here for the duration of the band.
        let sweeping = dragSession.marqueeSelection
        let ids = sweeping.isEmpty ? selectedShapeIds : sweeping
        // Handles are single-selection only: a set of 8 resize handles plus a rotate handle is
        // ~20 views with 9 drag gestures and 9 hover areas, they resize *one* shape (there is no
        // group bounding box), and past a handful of shapes they overlap into an unusable pile.
        // Mid-sweep every hit is provisional, so handles wait for the release that commits it.
        let showsHandles = sweeping.isEmpty && ids.count == 1
        if !ids.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(resolvedShapes) { shape in
                    if ids.contains(shape.id), shape.id != textEditingShapeId {
                        chrome(for: shape, showsHandles: showsHandles)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chrome(for shape: CanvasShapeModel, showsHandles: Bool) -> some View {
        let pendingR = dragSession.pendingResize[shape.id]
        let pendingRot = dragSession.pendingRotation[shape.id] ?? 0

        // Drag offset applies to the driver shape and — during a multi-select
        // drag — to every other unlocked selected shape that's moving with it.
        let draggingShapeId = dragSession.draggingShapeId
        let isPartOfDrag = draggingShapeId != nil && (shape.id == draggingShapeId || !showsHandles)
        let appliedDrag: CGSize = (isPartOfDrag && !shape.resolvedIsLocked) ? dragSession.activeDragOffset : .zero

        let displayRect = CanvasShapeDisplayGeometry.snappedRect(
            x: pendingR?.newX ?? (shape.x + appliedDrag.width),
            y: pendingR?.newY ?? (shape.y + appliedDrag.height),
            width: pendingR?.newW ?? shape.width,
            height: pendingR?.newH ?? shape.height,
            displayScale: visualScale,
            screenScale: screenScale
        )
        let currentRotation = shape.rotation + pendingRot

        if showsHandles {
            CanvasShapeHandlesOverlay(
                shape: shape,
                displayScale: visualScale,
                zoom: 1.0,
                displayRect: displayRect,
                currentRotation: currentRotation,
                handleDiameter: handleDiameter,
                rotationDelta: rotationBinding(for: shape.id),
                resizeState: resizeBinding(for: shape.id),
                onUpdate: onUpdate
            )
        } else {
            // No bindings built on this path: they are two closure pairs per shape, and a swept
            // row can hold dozens.
            ShapeSelectionOutline(
                isLocked: shape.resolvedIsLocked,
                displayRect: displayRect,
                rotation: currentRotation,
                zoom: 1.0
            )
        }
    }

    private func resizeBinding(for id: UUID) -> Binding<ResizeState?> {
        Binding(
            get: { dragSession.pendingResize[id] },
            set: { newValue in
                if let newValue {
                    dragSession.pendingResize[id] = newValue
                } else {
                    dragSession.pendingResize.removeValue(forKey: id)
                }
            }
        )
    }

    private func rotationBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { dragSession.pendingRotation[id] ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    dragSession.pendingRotation.removeValue(forKey: id)
                } else {
                    dragSession.pendingRotation[id] = newValue
                }
            }
        )
    }
}

/// Handle-free selection chrome: the outline, plus the lock badge that says why this shape won't
/// move with the rest. What a multi-selection and an in-flight marquee draw, and what
/// `CanvasShapeHandlesOverlay` builds on for a single selection.
struct ShapeSelectionOutline: View {
    let isLocked: Bool
    let displayRect: CGRect
    let rotation: Double
    let zoom: CGFloat

    var body: some View {
        outline
        if isLocked {
            lockedBadge
        }
    }

    private var outline: some View {
        Rectangle()
            .strokeBorder(
                isLocked ? Color.gray.opacity(UIMetrics.Opacity.lockedChrome) : Color.accentColor,
                lineWidth: (isLocked ? UIMetrics.BorderWidth.standard : UIMetrics.BorderWidth.emphasis) / zoom
            )
            .modifier(ShapeChromeFrame(displayRect: displayRect, rotation: rotation))
    }

    private var lockedBadge: some View {
        let badgeSize: CGFloat = 14 / zoom
        return ZStack(alignment: .topTrailing) {
            Color.clear
            Image(systemName: "lock.fill")
                .resizable()
                .scaledToFit()
                .frame(width: badgeSize, height: badgeSize)
                .foregroundStyle(Color.white)
                .padding(3 / zoom)
                .background(Color.gray.opacity(UIMetrics.Opacity.lockedBadgeFill), in: Circle())
                .padding(4 / zoom)
        }
        .modifier(ShapeChromeFrame(displayRect: displayRect, rotation: rotation))
    }
}

/// Sizes a chrome layer to a shape's display rect and rotates it about the shape's centre.
/// Every piece of selection chrome shares this placement, so it lives in one modifier.
struct ShapeChromeFrame: ViewModifier {
    let displayRect: CGRect
    let rotation: Double

    func body(content: Content) -> some View {
        content
            .frame(width: displayRect.width, height: displayRect.height)
            .rotationEffect(.degrees(rotation))
            .position(x: displayRect.midX, y: displayRect.midY)
            .allowsHitTesting(false)
    }
}
