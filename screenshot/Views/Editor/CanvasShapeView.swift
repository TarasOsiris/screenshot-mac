import SwiftUI
import UniformTypeIdentifiers

struct CanvasShapeView: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let isSelected: Bool
    var screenshotImage: NSImage?

    var showsEditorHelpers: Bool = true
    var onSelect: () -> Void
    var onUpdate: (CanvasShapeModel) -> Void
    var onDelete: () -> Void
    var onScreenshotDrop: ((NSImage) -> Void)?

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var resizeState: ResizeState?
    @State private var isDropTargeted = false
    @State private var isPickerPresented = false

    private var rotationRadians: CGFloat { shape.rotation * .pi / 180 }

    // Current effective geometry (accounts for in-progress resize or drag)
    private var effectiveX: CGFloat {
        if let rs = resizeState { return rs.newX } else { return shape.x + dragOffset.width }
    }
    private var effectiveY: CGFloat {
        if let rs = resizeState { return rs.newY } else { return shape.y + dragOffset.height }
    }
    private var effectiveW: CGFloat { resizeState?.newW ?? shape.width }
    private var effectiveH: CGFloat { resizeState?.newH ?? shape.height }

    private var displayX: CGFloat { effectiveX * displayScale }
    private var displayY: CGFloat { effectiveY * displayScale }
    private var displayW: CGFloat { effectiveW * displayScale }
    private var displayH: CGFloat { effectiveH * displayScale }

    @ViewBuilder
    var body: some View {
        let base = ZStack {
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
        
        if showsEditorHelpers {
            base
                .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.image]) { result in
                    if case .success(let url) = result,
                       let image = loadImportedImage(from: url) {
                        onScreenshotDrop?(image)
                    }
                }
                .gesture(dragGesture, including: .gesture)
                .simultaneousGesture(
                    TapGesture().onEnded { onSelect() }
                )
        } else {
            base
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            let deviceView = ZStack {
                DeviceFrameView(
                    category: shape.deviceCategory ?? .iphone,
                    bodyColor: shape.deviceBodyColor,
                    width: displayW,
                    height: displayH,
                    screenshotImage: screenshotImage
                )

                if screenshotImage == nil && showsEditorHelpers {
                    let iconSize = max(14, 20 * displayScale)
                    let labelSize = max(10, 10 * displayScale)
                    let spacing = max(4, 4 * displayScale)
                    let padding = max(10, 12 * displayScale)
                    let cornerRadius = max(8, 8 * displayScale)
                    let buttonBackgroundOpacity = isDropTargeted ? 0.9 : 1.0

                    Button {
                        isPickerPresented = true
                    } label: {
                        VStack(spacing: spacing) {
                            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                                .font(.system(size: iconSize))
                            Text(isDropTargeted ? "Drop image" : "Add image")
                                .font(.system(size: labelSize, weight: .medium))
                        }
                        .foregroundStyle(.primary)
                        .padding(padding)
                        .background(
                            .thinMaterial.opacity(buttonBackgroundOpacity),
                            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
                }

                if isDropTargeted && showsEditorHelpers {
                    RoundedRectangle(cornerRadius: max(8, 8 * displayScale), style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: max(8, 8 * displayScale), style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
                }
            }
            .frame(width: displayW, height: displayH)

            if showsEditorHelpers {
                deviceView.onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
            } else {
                deviceView
            }
        }
    }

    private var selectionOverlay: some View {
        Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 1.5)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(shape.rotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
            .allowsHitTesting(false)
    }

    // MARK: - Resize Handles

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
        }
        .frame(width: displayW, height: displayH)
        .rotationEffect(.degrees(shape.rotation))
        .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
    }

    private func handlePosition(for edge: ResizeEdge) -> CGPoint {
        let hw = displayW / 2
        let hh = displayH / 2
        switch edge {
        case .topLeft:     return CGPoint(x: 0, y: 0)
        case .top:         return CGPoint(x: hw, y: 0)
        case .topRight:    return CGPoint(x: displayW, y: 0)
        case .left:        return CGPoint(x: 0, y: hh)
        case .right:       return CGPoint(x: displayW, y: hh)
        case .bottomLeft:  return CGPoint(x: 0, y: displayH)
        case .bottom:      return CGPoint(x: hw, y: displayH)
        case .bottomRight: return CGPoint(x: displayW, y: displayH)
        }
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        let handleSize: CGFloat = 8
        let hitSize: CGFloat = 20
        let pos = handlePosition(for: edge)

        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())

            Circle()
                .fill(Color.white)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .frame(width: handleSize, height: handleSize)
                .allowsHitTesting(false)
        }
        .position(pos)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let tx = value.translation.width / displayScale
                    let ty = value.translation.height / displayScale
                    let lockAspectRatio = NSEvent.modifierFlags.contains(.shift) || shape.type == .device
                    resizeState = computeResize(edge: edge, tx: tx, ty: ty, lockAspectRatio: lockAspectRatio)
                }
                .onEnded { _ in
                    if let rs = resizeState {
                        var updated = shape
                        updated.x = rs.newX
                        updated.y = rs.newY
                        updated.width = rs.newW
                        updated.height = rs.newH
                        onUpdate(updated)
                    }
                    resizeState = nil
                }
        )
    }

    // MARK: - Resize Math

    /// Compute new x, y, width, height for a resize drag, keeping the anchor point fixed in canvas space.
    private func computeResize(edge: ResizeEdge, tx: CGFloat, ty: CGFloat, lockAspectRatio: Bool = false) -> ResizeState {
        let minSize: CGFloat = 20
        let cosA = cos(rotationRadians)
        let sinA = sin(rotationRadians)

        // Rotate screen-space drag into local shape space (cos(-x)=cos(x), sin(-x)=-sin(x))
        let localTx =  tx * cosA + ty * sinA
        let localTy = -tx * sinA + ty * cosA

        // Compute new size from local-space drag
        var newW = shape.width
        var newH = shape.height
        switch edge {
        case .topLeft:     newW = max(minSize, shape.width - localTx);  newH = max(minSize, shape.height - localTy)
        case .top:         newH = max(minSize, shape.height - localTy)
        case .topRight:    newW = max(minSize, shape.width + localTx);  newH = max(minSize, shape.height - localTy)
        case .left:        newW = max(minSize, shape.width - localTx)
        case .right:       newW = max(minSize, shape.width + localTx)
        case .bottomLeft:  newW = max(minSize, shape.width - localTx);  newH = max(minSize, shape.height + localTy)
        case .bottom:      newH = max(minSize, shape.height + localTy)
        case .bottomRight: newW = max(minSize, shape.width + localTx);  newH = max(minSize, shape.height + localTy)
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

        // Anchor point: the corner/edge opposite to the dragged one, in local coords relative to shape origin
        let anchor = edge.anchorPoint(width: shape.width, height: shape.height)

        // Anchor in canvas space: rotate around shape center
        let cx = shape.x + shape.width / 2
        let cy = shape.y + shape.height / 2
        let ax = anchor.x - shape.width / 2
        let ay = anchor.y - shape.height / 2
        let anchorCanvasX = cx + ax * cosA - ay * sinA
        let anchorCanvasY = cy + ax * sinA + ay * cosA

        // Same anchor in new local coords
        let newAnchor = edge.anchorPoint(width: newW, height: newH)
        let nax = newAnchor.x - newW / 2
        let nay = newAnchor.y - newH / 2

        // Solve for new center: newCenter + rotate(newAnchorRelCenter) = anchorCanvas
        let newCx = anchorCanvasX - (nax * cosA - nay * sinA)
        let newCy = anchorCanvasY - (nax * sinA + nay * cosA)

        return ResizeState(newX: newCx - newW / 2, newY: newCy - newH / 2, newW: newW, newH: newH)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSImage.self) { image, _ in
            if let image = image as? NSImage {
                DispatchQueue.main.async {
                    onScreenshotDrop?(image)
                }
            }
        }
        return true
    }

    private func loadImportedImage(from url: URL) -> NSImage? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return NSImage(contentsOf: url)
    }

    private func fontWeight(_ weight: Int) -> Font.Weight {
        switch weight {
        case ...299: .thin
        case 300...399: .light
        case 400...499: .regular
        case 500...599: .medium
        case 600...699: .semibold
        case 700...799: .bold
        default: .heavy
        }
    }
}

// MARK: - Resize Types

private struct ResizeState {
    var newX: CGFloat
    var newY: CGFloat
    var newW: CGFloat
    var newH: CGFloat
}

private enum ResizeEdge {
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
