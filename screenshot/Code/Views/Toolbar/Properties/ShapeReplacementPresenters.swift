import SwiftUI

/// The replace-SVG sheet and the macOS fill-image file panel for one shape, shared by the
/// properties bar and the selection inspector. iPad picks a fill image through `ImageSourceMenu`
/// inside `BackgroundImageEditor` instead.
private struct ShapeReplacementPresenters: ViewModifier, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    let fallbackShape: CanvasShapeModel
    @Binding var isReplacingSvg: Bool
    @Binding var isReplacingFillImage: Bool

    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .imageSourcePicker(isPresented: $isReplacingFillImage) { image in
                state.saveShapeFillImage(image, for: shapeId)
            }
            #endif
            .sheet(isPresented: $isReplacingSvg) {
                SvgPasteDialog(
                    isPresented: $isReplacingSvg,
                    replacing: editingShape(shapeId) ?? fallbackShape
                ) { svgContent, size, useColor, color in
                    state.replaceSvg(shapeId: shapeId, content: svgContent, naturalSize: size, useColor: useColor, color: color)
                }
            }
    }
}

extension View {
    func shapeReplacementPresenters(
        state: AppState,
        shapeId: UUID,
        fallbackShape: CanvasShapeModel,
        isReplacingSvg: Binding<Bool>,
        isReplacingFillImage: Binding<Bool>
    ) -> some View {
        modifier(ShapeReplacementPresenters(
            state: state,
            shapeId: shapeId,
            fallbackShape: fallbackShape,
            isReplacingSvg: isReplacingSvg,
            isReplacingFillImage: isReplacingFillImage
        ))
    }
}
