import SwiftUI
import UniformTypeIdentifiers

private extension View {
    /// Only applies `.compositingGroup()` when needed, avoiding offscreen bitmap allocation for shapes at full opacity.
    @ViewBuilder
    func compositingGroupIfNeeded(_ enabled: Bool) -> some View {
        if enabled { self.compositingGroup() } else { self }
    }
}

struct CanvasShapeView: View {
    @Environment(\.displayScale) private var screenScale

    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var screenshotImage: NSImage?
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color = CanvasShapeModel.defaultDeviceBodyColor
    var groupDragOffset: CGSize = .zero

    var clipBounds: CGRect?
    var showsEditorHelpers: Bool = true
    var onSelect: () -> Void
    var onShiftSelect: (() -> Void)?
    var onUpdate: (CanvasShapeModel) -> Void
    var onDelete: () -> Void
    var onScreenshotDrop: ((NSImage) -> Void)?
    var onClearImage: (() -> Void)?
    var onDragSnap: ((CanvasShapeModel, CGSize) -> SnapResult)?
    var onDragEnd: (() -> Void)?
    var onOptionDragDuplicate: ((UUID) -> UUID?)?
    var onDragProgress: ((CGSize) -> Void)?
    var onGroupDragEnd: ((CGSize) -> Void)?
    var onDidAppearAfterAdd: (() -> Void)?
    var onEditingTextChanged: ((Bool) -> Void)?
    var onMatchDeviceSizes: (() -> Void)?
    var onTranslate: (() -> Void)?
    var translateLocaleName: String?
    var availableFontFamilies: Set<String> = []

    @State private var addBumpScale: CGFloat = 1.0
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
    @State private var svgResizeDebounceTask: Task<Void, Never>?

    private let handleDiameter: CGFloat = 8

    private var rotationRadians: CGFloat { shape.rotation * .pi / 180 }
    private var displayPixelStep: CGFloat { 1 / max(screenScale, 1) }

    // Current effective geometry (accounts for in-progress resize or drag)
    private var effectiveX: CGFloat {
        if let rs = resizeState { return rs.newX } else { return shape.x + dragOffset.width + groupDragOffset.width }
    }
    private var effectiveY: CGFloat {
        if let rs = resizeState { return rs.newY } else { return shape.y + dragOffset.height + groupDragOffset.height }
    }
    private var effectiveW: CGFloat { resizeState?.newW ?? shape.width }
    private var effectiveH: CGFloat { resizeState?.newH ?? shape.height }

    private var displayRect: CGRect {
        let rawMinX = effectiveX * displayScale
        let rawMinY = effectiveY * displayScale
        let rawMaxX = (effectiveX + effectiveW) * displayScale
        let rawMaxY = (effectiveY + effectiveH) * displayScale

        let minX = snapToDisplayPixel(rawMinX)
        let minY = snapToDisplayPixel(rawMinY)
        let maxX = snapToDisplayPixel(rawMaxX)
        let maxY = snapToDisplayPixel(rawMaxY)

        return CGRect(
            x: minX,
            y: minY,
            width: max(displayPixelStep, maxX - minX),
            height: max(displayPixelStep, maxY - minY)
        )
    }
    private var displayX: CGFloat { displayRect.minX }
    private var displayY: CGFloat { displayRect.minY }
    private var displayW: CGFloat { displayRect.width }
    private var displayH: CGFloat { displayRect.height }
    private var displayOutlineWidth: CGFloat {
        guard let outlineWidth = shape.outlineWidth, outlineWidth > 0 else { return 0 }
        return max(displayPixelStep, snapToDisplayPixel(outlineWidth * displayScale))
    }

    private var currentRotation: Double {
        isEditingText ? 0 : shape.rotation + rotationDelta
    }

    /// Axis-aligned bounding box size for the rotated display rect.
    private var rotatedDisplaySize: CGSize {
        let rot = currentRotation.truncatingRemainder(dividingBy: 360)
        guard abs(rot) > 1e-6 else { return CGSize(width: displayW, height: displayH) }
        let rad = rot * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        return CGSize(
            width: displayW * cosA + displayH * sinA,
            height: displayW * sinA + displayH * cosA
        )
    }

    /// Path of the rotated rectangle within the AABB frame, for `.contentShape()`.
    private func rotatedRectangleHitPath(in bounds: CGSize) -> Path {
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        let rad = currentRotation * .pi / 180
        let cosA = cos(rad)
        let sinA = sin(rad)
        let hw = displayW / 2
        let hh = displayH / 2
        let corners = [
            CGPoint(x: cx + (-hw) * cosA - (-hh) * sinA, y: cy + (-hw) * sinA + (-hh) * cosA),
            CGPoint(x: cx + ( hw) * cosA - (-hh) * sinA, y: cy + ( hw) * sinA + (-hh) * cosA),
            CGPoint(x: cx + ( hw) * cosA - ( hh) * sinA, y: cy + ( hw) * sinA + ( hh) * cosA),
            CGPoint(x: cx + (-hw) * cosA - ( hh) * sinA, y: cy + (-hw) * sinA + ( hh) * cosA),
        ]
        var path = Path()
        path.move(to: corners[0])
        for i in 1..<corners.count { path.addLine(to: corners[i]) }
        path.closeSubpath()
        return path
    }

    @ViewBuilder
    var body: some View {
        let svgAware = clippedBase
            .onAppear {
                updateSvgCache()
                if let onDidAppearAfterAdd {
                    withAnimation(.easeOut(duration: 0.08)) {
                        addBumpScale = 1.12
                    } completion: {
                        withAnimation(.easeInOut(duration: 0.08)) {
                            addBumpScale = 1.0
                        }
                    }
                    onDidAppearAfterAdd()
                }
            }
            .onChange(of: isEditingText) { _, editing in
                onEditingTextChanged?(editing)
            }
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
            .onChange(of: shape.width) { debounceSvgCacheUpdate() }
            .onChange(of: shape.height) { debounceSvgCacheUpdate() }

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
                        } else if shape.type == .device || shape.type == .image {
                            isPickerPresented = true
                        }
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if NSEvent.modifierFlags.contains(.shift) {
                            onShiftSelect?()
                        } else {
                            onSelect()
                        }
                    }
                )
                .contextMenu { shapeContextMenu }

            if isSelected {
                handlesContent
                    .zIndex(99)
            }
        } else {
            svgAware
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var clippedBase: some View {
        let aabb = rotatedDisplaySize
        let dx = (aabb.width - displayW) / 2
        let dy = (aabb.height - displayH) / 2
        let offsetX = displayX - dx
        let offsetY = displayY - dy
        let hitPath = rotatedRectangleHitPath(in: aabb)
        let needsCompositing = shape.opacity < 1.0
        let base = ZStack {
            shapeContent
                .frame(width: displayW, height: displayH)
                .compositingGroupIfNeeded(needsCompositing)
                .opacity(shape.opacity)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(currentRotation))
        }
        .frame(width: aabb.width, height: aabb.height)
        .contentShape(hitPath)
        .scaleEffect(addBumpScale)
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let inside = hitPath.contains(location)
                if inside != isHovered {
                    isHovered = inside
                    if showsEditorHelpers && isSelected && !isDragging {
                        if inside {
                            NSCursor.openHand.set()
                        } else {
                            NSCursor.arrow.set()
                        }
                    }
                }
            case .ended:
                if isHovered {
                    isHovered = false
                    if showsEditorHelpers && isSelected && !isDragging {
                        NSCursor.arrow.set()
                    }
                }
            }
        }
        .offset(x: offsetX, y: offsetY)
        .overlay {
            if !isSelected && isHovered && showsEditorHelpers {
                hoverOverlay
            }
        }

        if let cb = clipBounds {
            let aabbRect = CGRect(x: offsetX, y: offsetY, width: aabb.width, height: aabb.height)
            if aabbRect.intersection(cb).isEmpty {
                base.allowsHitTesting(false).opacity(0)
            } else {
                let clippedCGPath = hitPath.offsetBy(dx: offsetX, dy: offsetY)
                    .cgPath.intersection(CGPath(rect: cb, transform: nil))
                let clippedHitPath = Path(clippedCGPath)
                if clippedHitPath.isEmpty {
                    base.allowsHitTesting(false).opacity(0)
                } else {
                    base
                        .contentShape(clippedHitPath)
                        .mask {
                            Rectangle()
                                .frame(width: cb.width, height: cb.height)
                                .position(x: cb.midX, y: cb.midY)
                        }
                }
            }
        } else {
            base
        }
    }

    @ViewBuilder
    private var shapeContent: some View {
        switch shape.type {
        case .rectangle:
            let rr = RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
            outlinedShape(rr)

        case .circle:
            outlinedShape(Ellipse())

        case .star:
            let star = StarShape(pointCount: shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)
            outlinedShape(star)

        case .text:
            if isEditingText {
                textEditor
            } else {
                let rawText = shape.text ?? ""
                let showPlaceholder = showsEditorHelpers && rawText.isEmpty
                let fontSize = shape.fontSize ?? 72
                let weight = fontWeight(shape.fontWeight ?? 700)
                let isItalic = showPlaceholder ? true : (shape.italic ?? false)
                let nsFont = resolvedNSFont(size: fontSize, weight: weight.nsWeight, italic: isItalic)
                DisplayTextView(
                    text: showPlaceholder ? "Text" : rawText,
                    font: nsFont,
                    color: NSColor(shape.color.opacity(showPlaceholder ? 0.4 : 1.0)),
                    alignment: shape.textAlign.nsTextAlignment,
                    verticalAlignment: shape.textVerticalAlign ?? .center,
                    uppercase: shape.uppercase ?? false,
                    letterSpacing: shape.letterSpacing,
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing
                )
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
            if let image = cachedSvgImage ?? Self.svgImage(from: shape.svgContent ?? "", useColor: shape.svgUseColor == true, color: shape.color, targetSize: CGSize(width: effectiveW, height: effectiveH)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
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

    @ViewBuilder
    private var shapeContextMenu: some View {
        if shape.type == .device || shape.type == .image {
            Button("Replace Image...") {
                isPickerPresented = true
            }
            Button("Reset Image") {
                onClearImage?()
            }
            .disabled(shape.displayImageFileName == nil)
            Divider()
        }
        if shape.type == .device {
            Menu("Change Device") {
                DeviceMenuContent(
                    onSelectCategory: { category in
                        var updated = shape
                        updated.selectAbstractDevice(category)
                        onUpdate(updated)
                    },
                    onSelectFrame: { frame in
                        var updated = shape
                        updated.selectRealFrame(frame)
                        onUpdate(updated)
                    }
                )
            }
            if let onMatchDeviceSizes {
                Button("Resize to Fit All Devices") {
                    onMatchDeviceSizes()
                }
            }
            Divider()
        }
        if shape.type == .text {
            Picker("Align", selection: Binding(
                get: { shape.textAlign ?? .center },
                set: { var updated = shape; updated.textAlign = $0; onUpdate(updated) }
            )) {
                Label("Left", systemImage: "text.alignleft").tag(TextAlign.left)
                Label("Center", systemImage: "text.aligncenter").tag(TextAlign.center)
                Label("Right", systemImage: "text.alignright").tag(TextAlign.right)
            }
            Toggle("Italic", isOn: Binding(
                get: { shape.italic ?? false },
                set: { var updated = shape; updated.italic = $0; onUpdate(updated) }
            ))
            Toggle("Uppercase", isOn: Binding(
                get: { shape.uppercase ?? false },
                set: { var updated = shape; updated.uppercase = $0; onUpdate(updated) }
            ))
            if let onTranslate, let localeName = translateLocaleName {
                Divider()
                Button("Translate into \(localeName)") {
                    onTranslate()
                }
                .disabled((shape.text ?? "").isEmpty)
            }
            Divider()
        }
        if shape.type == .svg {
            Toggle("Use Custom Color", isOn: Binding(
                get: { shape.svgUseColor ?? false },
                set: { var updated = shape; updated.svgUseColor = $0; onUpdate(updated) }
            ))
            Divider()
        }
        if shape.type == .star {
            Menu("Points: \(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)") {
                ForEach(3...12, id: \.self) { count in
                    Button("\(count)") {
                        var updated = shape
                        updated.starPointCount = count
                        onUpdate(updated)
                    }
                }
            }
            Divider()
        }
        Toggle("Clip to Screenshot", isOn: Binding(
            get: { shape.clipToTemplate ?? false },
            set: { var updated = shape; updated.clipToTemplate = $0; onUpdate(updated) }
        ))
        Divider()
        Button("Delete", role: .destructive) {
            onDelete()
        }
    }

    @ViewBuilder
    private var handlesContent: some View {
        if isSelected {
            selectionOverlay
            resizeHandles
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

    private func snapToDisplayPixel(_ value: CGFloat) -> CGFloat {
        (value / displayPixelStep).rounded() * displayPixelStep
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
        let minSize: CGFloat = shape.type == .device ? CanvasShapeModel.deviceMinSize : 20
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

                    // Don't call onSelect if shape is already part of a multi-selection
                    if !isMultiSelected {
                        onSelect()
                    }
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
                // Report drag progress for group drag
                if isMultiSelected {
                    onDragProgress?(dragOffset)
                }
            }
            .onEnded { _ in
                NSCursor.arrow.set()
                let finalOffset = dragOffset
                dragOffset = .zero
                isDragging = false
                if isMultiSelected {
                    onGroupDragEnd?(finalOffset)
                } else {
                    var updated = shape
                    updated.x += finalOffset.width
                    updated.y += finalOffset.height
                    onUpdate(updated)
                }
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
        // Scale button to fit within shape, capped at comfortable max
        let sizeRef = min(displayW, displayH)
        let iconSize = min(28, max(14, sizeRef * 0.18))
        let padding = min(12, max(4, sizeRef * 0.05))
        let cr = min(8, max(4, sizeRef * 0.04))

        ZStack {
            background()

            Button {
                isPickerPresented = true
            } label: {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: iconSize))
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

    private func debounceSvgCacheUpdate() {
        svgResizeDebounceTask?.cancel()
        svgResizeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            guard !Task.isCancelled else { return }
            updateSvgCache()
        }
    }

    private func updateSvgCache() {
        guard shape.type == .svg, let content = shape.svgContent else { return }
        let w = Int(effectiveW)
        let h = Int(effectiveH)
        let key = "\(content.hashValue)-\(shape.svgUseColor ?? false)-\(shape.color.hexString)-\(w)x\(h)"
        guard key != svgCacheKey else { return }
        svgCacheKey = key
        let targetSize = CGSize(width: effectiveW, height: effectiveH)
        cachedSvgImage = Self.svgImage(from: content, useColor: shape.svgUseColor == true, color: shape.color, targetSize: targetSize)
    }

    static func svgImage(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize? = nil) -> NSImage? {
        SvgHelper.renderImage(from: svgContent, useColor: useColor, color: color, targetSize: targetSize)
    }

    private var textEditor: some View {
        let fontSize = shape.fontSize ?? 72
        let weight = fontWeight(shape.fontWeight ?? 700)
        let nsFont = resolvedNSFont(size: fontSize, weight: weight.nsWeight, italic: shape.italic ?? false)
        return InlineTextEditor(
            text: $editingTextValue,
            font: nsFont,
            color: NSColor(shape.color),
            alignment: shape.textAlign.nsTextAlignment,
            uppercase: shape.uppercase ?? false,
            letterSpacing: shape.letterSpacing,
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
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

    @ViewBuilder
    private func outlinedShape<S: InsettableShape>(_ outline: S) -> some View {
        if shape.resolvedFillStyle == .color {
            outline
                .fill(shape.color)
                .overlay {
                    if let outlineColor = shape.outlineColor, displayOutlineWidth > 0 {
                        outline.strokeBorder(
                            outlineColor,
                            style: StrokeStyle(lineWidth: displayOutlineWidth, lineJoin: .miter)
                        )
                    }
                }
        } else {
            outline
                .fill(.clear)
                .overlay {
                    shape.fillView(image: fillImage, modelSize: CGSize(width: shape.width, height: shape.height))
                        .clipShape(outline)
                }
                .overlay {
                    if let outlineColor = shape.outlineColor, displayOutlineWidth > 0 {
                        outline.strokeBorder(
                            outlineColor,
                            style: StrokeStyle(lineWidth: displayOutlineWidth, lineJoin: .miter)
                        )
                    }
                }
        }
    }

    /// The custom font family name, if the shape specifies one that's available.
    private var customFontName: String? {
        guard let name = shape.fontName, !name.isEmpty,
              availableFontFamilies.contains(name) else { return nil }
        return name
    }

    private func resolvedFont(size: CGFloat, weight: Font.Weight) -> Font {
        // Use Font.custom for custom fonts — Font(NSFont) can lose variable font
        // weight variations. Font.custom lets SwiftUI resolve weight axes natively.
        if let name = customFontName {
            return Font.custom(name, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }

    private func resolvedNSFont(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont {
        let baseFont: NSFont
        if let name = customFontName {
            let fm = NSFontManager.shared
            let fmWeight = Self.fontManagerWeight(for: weight)
            if let font = fm.font(withFamily: name, traits: [], weight: fmWeight, size: size) {
                baseFont = font
            } else if let font = fm.font(withFamily: name, traits: [], weight: 5, size: size) {
                baseFont = fmWeight >= 9 ? fm.convert(font, toHaveTrait: .boldFontMask) : font
            } else {
                baseFont = CTFontCreateWithName(name as CFString, size, nil) as NSFont
            }
        } else {
            baseFont = NSFont.systemFont(ofSize: size, weight: weight)
        }
        return italicized(baseFont, italic: italic)
    }

    private func italicized(_ font: NSFont, italic: Bool) -> NSFont {
        guard italic else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    /// Maps NSFont.Weight to the 0–15 integer scale used by NSFontManager,
    /// avoiding creation of a throwaway system font just to query its weight.
    private static func fontManagerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: return 2
        case .thin:       return 3
        case .light:      return 4
        case .regular:    return 5
        case .medium:     return 6
        case .semibold:   return 8
        case .bold:       return 9
        case .heavy:      return 11
        case .black:      return 14
        default:          return 5
        }
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
