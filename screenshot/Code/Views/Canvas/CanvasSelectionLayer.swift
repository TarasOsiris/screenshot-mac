import SwiftUI

/// The single owner of selection chrome (outlines + resize/rotation handles)
/// for both single- and multi-select. Sits above the whole shape layer so
/// handles always paint on top and stay grabbable even when the shape is
/// behind another — don't reintroduce inline handles in `CanvasShapeView`.
/// Drawn at the canvas's full (zoom-inclusive) `visualScale` so handle and
/// outline thickness stay pixel-perfect at every zoom level.
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
    private var isMultiSelected: Bool { selectedShapeIds.count > 1 }

    var body: some View {
        let selectedIds = selectedShapeIds
        if !selectedIds.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(resolvedShapes) { shape in
                    if selectedIds.contains(shape.id), shape.id != textEditingShapeId {
                        handles(for: shape)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func handles(for shape: CanvasShapeModel) -> some View {
        let pendingR = dragSession.pendingResize[shape.id]
        let pendingRot = dragSession.pendingRotation[shape.id] ?? 0

        // Drag offset applies to the driver shape and — during a multi-select
        // drag — to every other unlocked selected shape that's moving with it.
        let draggingShapeId = dragSession.draggingShapeId
        let isPartOfDrag = draggingShapeId != nil && (shape.id == draggingShapeId || isMultiSelected)
        let appliedDrag: CGSize = (isPartOfDrag && !shape.resolvedIsLocked) ? dragSession.activeDragOffset : .zero

        let effectiveX = (pendingR?.newX ?? (shape.x + appliedDrag.width))
        let effectiveY = (pendingR?.newY ?? (shape.y + appliedDrag.height))
        let effectiveW = pendingR?.newW ?? shape.width
        let effectiveH = pendingR?.newH ?? shape.height

        let displayRect = CanvasShapeDisplayGeometry.snappedRect(
            x: effectiveX,
            y: effectiveY,
            width: effectiveW,
            height: effectiveH,
            displayScale: visualScale,
            screenScale: screenScale
        )
        let currentRotation = shape.rotation + pendingRot

        CanvasShapeHandlesOverlay(
            shape: shape,
            displayScale: visualScale,
            zoom: 1.0,
            displayX: displayRect.minX,
            displayY: displayRect.minY,
            displayW: displayRect.width,
            displayH: displayRect.height,
            currentRotation: currentRotation,
            handleDiameter: handleDiameter,
            rotationDelta: rotationBinding(for: shape.id),
            resizeState: resizeBinding(for: shape.id),
            onUpdate: onUpdate
        )
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
