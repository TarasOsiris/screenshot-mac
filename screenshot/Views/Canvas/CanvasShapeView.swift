import SwiftUI
import UniformTypeIdentifiers

struct CanvasShapeView: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let isSelected: Bool
    var screenshotImage: NSImage?
    var defaultDeviceBodyColor: Color = CanvasShapeModel.defaultDeviceBodyColor

    var showsEditorHelpers: Bool = true
    var onSelect: () -> Void
    var onUpdate: (CanvasShapeModel) -> Void
    var onDelete: () -> Void
    var onScreenshotDrop: ((NSImage) -> Void)?
    var onDragSnap: ((CanvasShapeModel, CGSize) -> SnapResult)?
    var onDragEnd: (() -> Void)?
    var onOptionDragDuplicate: ((UUID) -> UUID?)?

    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var resizeState: ResizeState?
    @State private var isDropTargeted = false
    @State private var isPickerPresented = false
    @State private var isEditingText = false
    @State private var editingTextValue = ""
    @State private var cachedSvgImage: NSImage?
    @State private var svgCacheKey = ""
    @State private var rotationDelta: Double = 0

    private let handleDiameter: CGFloat = 8

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

    private var currentRotation: Double { shape.rotation + rotationDelta }

    @ViewBuilder
    var body: some View {
        let base = ZStack {
            shapeContent
                .frame(width: displayW, height: displayH)
                .opacity(shape.opacity)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(currentRotation))
        }
        .frame(width: displayW, height: displayH)
        .onHover { hovering in
            isHovered = hovering
            if showsEditorHelpers && isSelected && !isDragging {
                if hovering {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
        }
        .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
        .overlay {
            if isSelected {
                selectionOverlay
                resizeHandles
            } else if isHovered && showsEditorHelpers {
                hoverOverlay
            }
        }

        let svgAware = base
            .onAppear { updateSvgCache() }
            .onChange(of: isSelected) { _, selected in
                if !selected && isEditingText {
                    commitTextEdit()
                }
            }
            .onDisappear {
                if isEditingText {
                    commitTextEdit()
                }
            }
            .onChange(of: shape.svgContent) { updateSvgCache() }
            .onChange(of: shape.svgUseColor) { updateSvgCache() }
            .onChange(of: shape.color) { updateSvgCache() }

        if showsEditorHelpers {
            svgAware
                .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.image]) { result in
                    if case .success(let url) = result,
                       let image = loadImportedImage(from: url) {
                        onScreenshotDrop?(image)
                    }
                }
                .gesture(dragGesture, including: .gesture)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        if shape.type == .text {
                            editingTextValue = shape.text ?? ""
                            isEditingText = true
                            onSelect()
                        }
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded { onSelect() }
                )
        } else {
            svgAware
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
                .fill(shape.color, style: FillStyle(eoFill: false, antialiased: true))

        case .text:
            if isEditingText {
                textEditor
            } else {
                let rawText = shape.text ?? ""
                let showPlaceholder = showsEditorHelpers && rawText.isEmpty
                let displayText = showPlaceholder ? "Text" : rawText
                Text(displayText)
                    .font(resolvedFont(size: shape.fontSize ?? 72, weight: fontWeight(shape.fontWeight ?? 700)))
                    .italic(showPlaceholder ? true : (shape.italic ?? false))
                    .tracking(shape.letterSpacing ?? 0)
                    .lineSpacing(shape.lineSpacing ?? 0)
                    .foregroundStyle(shape.color.opacity(showPlaceholder ? 0.4 : 1.0))
                    .multilineTextAlignment(shape.textAlign.textAlignment)
                    .frame(width: effectiveW, height: effectiveH)
                    .scaleEffect(displayScale, anchor: .topLeading)
                    .frame(width: displayW, height: displayH, alignment: .topLeading)
            }

        case .image:
            if let image = screenshotImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: displayW, height: displayH)
                    .clipShape(RoundedRectangle(cornerRadius: shape.borderRadius * displayScale))
            } else if showsEditorHelpers {
                imageDropPlaceholder {
                    RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
                        .fill(Color.gray.opacity(0.3))
                }
            }

        case .svg:
            if let image = cachedSvgImage ?? Self.svgImage(from: shape.svgContent ?? "", useColor: shape.svgUseColor == true, color: shape.color) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else if showsEditorHelpers {
                RoundedRectangle(cornerRadius: 4 * displayScale)
                    .fill(Color.gray.opacity(0.2))
                    .overlay {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 24 * displayScale))
                            .foregroundStyle(.secondary)
                    }
            }

        case .device:
            let frame = DeviceFrameView(
                category: shape.deviceCategory ?? .iphone,
                bodyColor: shape.resolvedDeviceBodyColor(default: defaultDeviceBodyColor),
                width: displayW,
                height: displayH,
                screenshotImage: screenshotImage,
                deviceFrameId: shape.deviceFrameId
            )
            if screenshotImage == nil && showsEditorHelpers {
                imageDropPlaceholder { frame }
            } else if showsEditorHelpers {
                frame
                    .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                        handleDrop(providers)
                    }
            } else {
                frame
            }
        }
    }

    private var selectionOverlay: some View {
        borderOverlay(opacity: 1.0, lineWidth: 1.5)
    }

    private var hoverOverlay: some View {
        borderOverlay(opacity: 0.5, lineWidth: 1)
    }

    private func borderOverlay(opacity: Double, lineWidth: CGFloat) -> some View {
        Rectangle()
            .strokeBorder(Color.accentColor.opacity(opacity), lineWidth: lineWidth)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(currentRotation))
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
            rotateHandleContent
        }
        .frame(width: displayW, height: displayH)
        .rotationEffect(.degrees(currentRotation))
        .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
    }

    // MARK: - Rotate Handle

    private var rotateHandleContent: some View {
        let stemLength: CGFloat = 24
        let handleSize: CGFloat = 10
        let hitSize: CGFloat = 24

        return ZStack {
            // Stem line behind the knob (starts below the resize handle's edge)
            Path { path in
                path.move(to: CGPoint(x: displayW / 2, y: -handleDiameter / 2))
                path.addLine(to: CGPoint(x: displayW / 2, y: -stemLength))
            }
            .stroke(Color.accentColor, lineWidth: 1)

            // Rotate handle circle (on top of stem)
            ZStack {
                Color.clear
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())

                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)

                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
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

    /// Rotation gesture using translation-only math (no need for global center position).
    /// The handle starts at a known offset from center in screen space; we compute angle change
    /// from the translation vector applied to that initial offset.
    private func rotateGesture(stemLength: CGFloat) -> some Gesture {
        let handleDist = displayH / 2 + stemLength
        let baseAngleRad = (shape.rotation - 90) * .pi / 180
        // Pre-compute invariant vector from center to handle start position
        let handleVecX = handleDist * cos(baseAngleRad)
        let handleVecY = handleDist * sin(baseAngleRad)
        let startAngle = atan2(handleVecY, handleVecX) * 180 / .pi

        return DragGesture(coordinateSpace: .global)
            .onChanged { value in
                CursorHelper.rotateCursor.set()

                // Current vector: initial + drag translation
                let curX = handleVecX + value.translation.width
                let curY = handleVecY + value.translation.height
                let currentAngle = atan2(curY, curX) * 180 / .pi

                var delta = currentAngle - startAngle

                // Snap to 15° increments when holding Shift
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
        var a = angle.truncatingRemainder(dividingBy: 360)
        if a < 0 { a += 360 }
        return a
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
        let handleSize = handleDiameter
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
        .onHover { hovering in
            if hovering {
                CursorHelper.resizeCursor(for: edge, rotation: currentRotation).push()
            } else {
                NSCursor.pop()
            }
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
                    NSCursor.closedHand.set()

                    // Option+drag: leave original in place, create & drag a copy
                    if NSEvent.modifierFlags.contains(.option) {
                        _ = onOptionDragDuplicate?(shape.id)
                    }

                    onSelect()
                }
                let rawOffset = CGSize(
                    width: value.translation.width / displayScale,
                    height: value.translation.height / displayScale
                )
                if let snap = onDragSnap?(shape, rawOffset) {
                    dragOffset = snap.snappedOffset
                } else {
                    dragOffset = rawOffset
                }
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                var updated = shape
                updated.x += dragOffset.width
                updated.y += dragOffset.height
                dragOffset = .zero
                isDragging = false
                onUpdate(updated)
                onDragEnd?()
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
        NSImage.fromSecurityScopedURL(url)
    }

    @ViewBuilder
    private func imageDropPlaceholder<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        let iconSize = max(14, 20 * displayScale)
        let labelSize = max(10, 10 * displayScale)
        let spacing = max(4, 4 * displayScale)
        let padding = max(10, 12 * displayScale)
        let cr = max(8, 8 * displayScale)

        ZStack {
            background()

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
                    .thinMaterial.opacity(isDropTargeted ? 0.9 : 1.0),
                    in: RoundedRectangle(cornerRadius: cr, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                RoundedRectangle(cornerRadius: cr, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
            }
        }
        .frame(width: displayW, height: displayH)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func updateSvgCache() {
        guard shape.type == .svg, let content = shape.svgContent else { return }
        let key = "\(content.hashValue)-\(shape.svgUseColor ?? false)-\(shape.color.hexString)"
        guard key != svgCacheKey else { return }
        svgCacheKey = key
        cachedSvgImage = Self.svgImage(from: content, useColor: shape.svgUseColor == true, color: shape.color)
    }

    static func svgImage(from svgContent: String, useColor: Bool, color: Color) -> NSImage? {
        var svg = svgContent
        if useColor {
            let hex = color.hexString
            // Replace fill attributes with the chosen color, preserving fill="none"
            svg = svg.replacingOccurrences(
                of: "fill\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "fill=\"\(hex)\"",
                options: .regularExpression
            )
            // Replace stroke attributes, preserving stroke="none"
            svg = svg.replacingOccurrences(
                of: "stroke\\s*=\\s*\"(?!none\")[^\"]*\"",
                with: "stroke=\"\(hex)\"",
                options: .regularExpression
            )
        }
        guard let data = svg.data(using: .utf8) else { return nil }
        return NSImage(data: data)
    }

    private var textEditor: some View {
        let fontSize = shape.fontSize ?? 72
        let weight = fontWeight(shape.fontWeight ?? 700)
        let nsFont = resolvedNSFont(size: fontSize, weight: weight.nsWeight)
        return InlineTextEditor(
            text: $editingTextValue,
            font: nsFont,
            color: NSColor(shape.color),
            alignment: shape.textAlign.nsTextAlignment,
            onCommit: { commitTextEdit() }
        )
        .frame(width: effectiveW, height: effectiveH)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    private func commitTextEdit() {
        guard isEditingText else { return }
        isEditingText = false
        var updated = shape
        updated.text = editingTextValue
        onUpdate(updated)
    }

    private func resolvedFont(size: CGFloat, weight: Font.Weight) -> Font {
        Font(resolvedNSFont(size: size, weight: weight.nsWeight))
    }

    private func resolvedNSFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let name = shape.fontName, !name.isEmpty {
            let fm = NSFontManager.shared
            let nsFontWeight = fm.weight(of: NSFont.systemFont(ofSize: size, weight: weight))
            return fm.font(withFamily: name, traits: [], weight: nsFontWeight, size: size)
                ?? NSFont.systemFont(ofSize: size, weight: weight)
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
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
