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

    private var displayX: CGFloat { (shape.x + dragOffset.width) * displayScale }
    private var displayY: CGFloat { (shape.y + dragOffset.height) * displayScale }
    private var displayW: CGFloat { shape.width * displayScale }
    private var displayH: CGFloat { shape.height * displayScale }

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
                .multilineTextAlignment(textAlignment(shape.textAlign))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .image:
            RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
                .fill(shape.color.opacity(0.3))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 24 * displayScale))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var selectionOverlay: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(shape.rotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
    }

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

    private func textAlignment(_ align: String?) -> TextAlignment {
        switch align {
        case "left": .leading
        case "right": .trailing
        default: .center
        }
    }
}
