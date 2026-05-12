import SwiftUI

/// Renders selection outlines and resize/rotation handles for the row's
/// selected shapes. Lives **outside** the row canvas's `.scaleEffect(zoom)`
/// so handle and outline thickness stay pixel-perfect at every zoom level.
struct CanvasSelectionLayer: View {
    @Environment(\.displayScale) private var screenScale

    @Bindable var state: AppState
    let row: ScreenshotRow
    /// Resolved shapes (with locale overrides applied) — shared with the
    /// row's shape layer so we don't repeat `LocaleService.resolveShapes` here.
    let resolvedShapes: [CanvasShapeModel]
    /// Visual scale: model points × (base displayScale × zoom).
    let visualScale: CGFloat
    @Binding var pendingResize: [UUID: ResizeState]
    @Binding var pendingRotation: [UUID: Double]
    let textEditingShapeId: UUID?
    let activeDragOffset: CGSize
    let draggingShapeId: UUID?

    private let handleDiameter: CGFloat = 8

    var body: some View {
        let selectedIds = state.selectedShapeIds
        if selectedIds.count > 1 {
            ZStack(alignment: .topLeading) {
                ForEach(resolvedShapes) { shape in
                    if selectedIds.contains(shape.id), shape.id != textEditingShapeId {
                        handles(for: shape, isMultiSelected: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func handles(for shape: CanvasShapeModel, isMultiSelected: Bool) -> some View {
        let pendingR = pendingResize[shape.id]
        let pendingRot = pendingRotation[shape.id] ?? 0

        // Drag offset applies to the driver shape and — during a multi-select
        // drag — to every other unlocked selected shape that's moving with it.
        let isPartOfDrag = draggingShapeId != nil && (shape.id == draggingShapeId || isMultiSelected)
        let appliedDrag: CGSize = (isPartOfDrag && !shape.resolvedIsLocked) ? activeDragOffset : .zero

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
            onUpdate: { state.updateShape($0) }
        )
    }

    private func resizeBinding(for id: UUID) -> Binding<ResizeState?> {
        Binding(
            get: { pendingResize[id] },
            set: { newValue in
                if let newValue {
                    pendingResize[id] = newValue
                } else {
                    pendingResize.removeValue(forKey: id)
                }
            }
        )
    }

    private func rotationBinding(for id: UUID) -> Binding<Double> {
        Binding(
            get: { pendingRotation[id] ?? 0 },
            set: { newValue in
                if newValue == 0 {
                    pendingRotation.removeValue(forKey: id)
                } else {
                    pendingRotation[id] = newValue
                }
            }
        )
    }
}
