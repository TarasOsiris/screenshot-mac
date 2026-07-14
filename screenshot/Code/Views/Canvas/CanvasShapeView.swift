import SwiftUI

private extension View {
    /// Only applies `.compositingGroup()` when needed, avoiding offscreen bitmap allocation for shapes at full opacity.
    @ViewBuilder
    func compositingGroupIfNeeded(_ enabled: Bool) -> some View {
        if enabled { self.compositingGroup() } else { self }
    }
}

/// Single-entry memo for the rotated clipped hit path. Plain (non-observable)
/// class held in `@State` so writing to it during body evaluation is legal and
/// triggers nothing.
final class ClipPathMemo {
    struct Key: Equatable {
        var offsetX: CGFloat
        var offsetY: CGFloat
        var displayW: CGFloat
        var displayH: CGFloat
        var rotation: Double
        var clipBounds: CGRect
    }

    var key: Key?
    var path = Path()
}

struct CanvasShapeView: View {
    @Environment(\.displayScale) private var screenScale

    let shape: CanvasShapeModel
    let displayScale: CGFloat
    var zoom: CGFloat = 1.0
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var screenshotImage: NSImage?
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color = CanvasShapeModel.defaultDeviceBodyColor
    var deviceModelRenderingMode: DeviceModelRenderingMode = .snapshot

    var clipBounds: CGRect?
    var showsEditorHelpers: Bool = true
    var allowSynchronousSvgRender = true
    /// Editor-only transient drag/resize/rotate state. Nil in export/preview
    /// paths. Read through the gated computed properties below so shapes that
    /// aren't part of the interaction never observe per-tick session changes.
    var dragSession: CanvasDragSession?
    var availableFontFamilies: Set<String> = []
    var interactions = CanvasShapeInteractions()

    @State var addBumpScale: CGFloat = 1.0
    @State var dragOffset: CGSize = .zero
    @State var isDragging = false
    @State private var isHovered = false
    @State var isDropTargeted = false
    @State var isPickerPresented = false
    @State var isEditingText = false
    @State var editingTextValue = ""
    @State var editingRichTextData: String?
    @State var selectionState: RichTextSelectionState?
    @StateObject var formatController = RichTextFormatController()
    @State var cachedSvgImage: NSImage?
    @State var svgCacheKey = ""
    @State var svgResizeDebounceTask: Task<Void, Never>?
    @State private var clipPathMemo = ClipPathMemo()

    private var displayPixelStep: CGFloat { 1 / max(screenScale, 1) }

    /// In-progress resize reported by the selection overlay. Gated on `isSelected`
    /// so unselected shapes never subscribe to the session's per-tick mutations.
    var resizeState: ResizeState? {
        guard isSelected, let dragSession else { return nil }
        return dragSession.pendingResize[shape.id]
    }

    var rotationDelta: Double {
        guard isSelected, let dragSession else { return 0 }
        return dragSession.pendingRotation[shape.id] ?? 0
    }

    /// Offset applied to the other shapes of a multi-selection while one of them
    /// is dragged. Locked shapes don't follow — `applyGroupDrag` skips them at
    /// commit time, so following visually would snap back on release. The guard
    /// order matters: the driver bails on `draggingId != shape.id` before ever
    /// reading `activeDragOffset` (its local `dragOffset` drives it), so it isn't
    /// re-invalidated by its own per-tick session writes.
    var groupDragOffset: CGSize {
        guard isMultiSelected, !shape.resolvedIsLocked,
              let dragSession,
              let draggingId = dragSession.draggingShapeId,
              draggingId != shape.id else { return .zero }
        return dragSession.activeDragOffset
    }

    // Current effective geometry (accounts for in-progress resize or drag)
    var effectiveX: CGFloat {
        if let rs = resizeState { return rs.newX } else { return shape.x + dragOffset.width + groupDragOffset.width }
    }
    var effectiveY: CGFloat {
        if let rs = resizeState { return rs.newY } else { return shape.y + dragOffset.height + groupDragOffset.height }
    }
    var effectiveW: CGFloat { resizeState?.newW ?? shape.width }
    var effectiveH: CGFloat { resizeState?.newH ?? shape.height }

    private var displayRect: CGRect {
        CanvasShapeDisplayGeometry.snappedRect(
            x: effectiveX,
            y: effectiveY,
            width: effectiveW,
            height: effectiveH,
            displayScale: displayScale,
            screenScale: screenScale
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
            .onAppear(perform: handleAppear)
            .onChange(of: isEditingText) { _, editing in
                handleEditingStateChange(editing)
            }
            .onChange(of: selectionState) { _, newState in
                handleSelectionStateChange(newState)
            }
            .onChange(of: isSelected) { _, selected in
                handleSelectionChange(selected)
            }
            .onDisappear(perform: handleDisappear)
            .onChange(of: shape.svgContent) { updateSvgCache() }
            .onChange(of: shape.svgUseColor) { updateSvgCache() }
            .onChange(of: shape.color) { updateSvgCache() }
            .onChange(of: shape.width) { debounceSvgCacheUpdate() }
            .onChange(of: shape.height) { debounceSvgCacheUpdate() }

        // One structure for both edit and view mode. `showsEditorHelpers` toggles only
        // modifier *values* (hit-testing, handle visibility) — never view identity — so
        // switching modes can't tear down / rebuild the shape (which blinked and broke
        // z-order as SwiftUI re-rendered SceneKit/SVG content and re-inserted the view).
        ZStack(alignment: .topLeading) {
            svgAware
                .gesture(dragGesture, including: .gesture)
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        handleDoubleTap()
                    }
                )
                .simultaneousGesture(
                    TapGesture().onEnded {
                        handleTap()
                    }
                )
                .allowsHitTesting(showsEditorHelpers)
        }
        // Anchor the image-source picker popup at the device's visual center. Lives in a
        // `.background` (sharing this view's top-leading origin) rather than as a ZStack
        // sibling so its greedy `.position` doesn't expand the shape view to fill the canvas.
        .background(alignment: .topLeading) {
            Color.clear
                .frame(width: displayW, height: displayH)
                .imageSourcePicker(isPresented: $isPickerPresented) { image in
                    interactions.onScreenshotDrop?(image)
                }
                .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
                .allowsHitTesting(false)
        }
        .accessibilityHidden(!showsEditorHelpers)
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
                .overlay { formatBarAnchorReader }
                .compositingGroupIfNeeded(needsCompositing)
                .opacity(shape.opacity)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(currentRotation))
        }
        .frame(width: aabb.width, height: aabb.height)
        .contentShape(hitPath)
        .scaleEffect(addBumpScale)
        // No custom preview: the canvas now renders at full scale (EditorRowView), so a shape's
        // layout frame equals its on-screen size and iOS's default lift snapshots the existing
        // on-screen pixels at the right size. A custom preview re-evaluates the view in an
        // offscreen pass, which re-runs the device SceneKit snapshot and renders devices wrong.
        .contextMenu {
            shapeContextMenu
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let inside = hitPath.contains(location)
                if inside != isHovered {
                    isHovered = inside
                    if showsEditorHelpers && isSelected && !isDragging {
                        PlatformCursor.setHover(grabbable: inside && !shape.resolvedIsLocked)
                    }
                }
            case .ended:
                if isHovered {
                    isHovered = false
                    if showsEditorHelpers && isSelected && !isDragging {
                        PlatformCursor.setArrow()
                    }
                }
            @unknown default:
                break
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
                let clippedHitPath = clippedHitPath(
                    hitPath: hitPath,
                    offsetX: offsetX,
                    offsetY: offsetY,
                    aabbRect: aabbRect,
                    clipBounds: cb
                )
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

    /// `CGPath.intersection` is a geometric boolean op — too expensive to run on
    /// every body eval. Unrotated shapes reduce to a rect∩rect; rotated ones are
    /// memoized on the inputs the path depends on.
    private func clippedHitPath(
        hitPath: Path,
        offsetX: CGFloat,
        offsetY: CGFloat,
        aabbRect: CGRect,
        clipBounds cb: CGRect
    ) -> Path {
        let rotation = currentRotation.truncatingRemainder(dividingBy: 360)
        if abs(rotation) < 1e-6 {
            return Path(aabbRect.intersection(cb))
        }
        let key = ClipPathMemo.Key(
            offsetX: offsetX,
            offsetY: offsetY,
            displayW: displayW,
            displayH: displayH,
            rotation: rotation,
            clipBounds: cb
        )
        if clipPathMemo.key == key { return clipPathMemo.path }
        let clipped = Path(
            hitPath.offsetBy(dx: offsetX, dy: offsetY)
                .cgPath.intersection(CGPath(rect: cb, transform: nil))
        )
        clipPathMemo.key = key
        clipPathMemo.path = clipped
        return clipped
    }

    @ViewBuilder
    private var shapeContent: some View {
        CanvasShapeRenderContent(
            shape: shape,
            effectiveW: effectiveW,
            effectiveH: effectiveH,
            displayW: displayW,
            displayH: displayH,
            displayScale: displayScale,
            displayOutlineWidth: displayOutlineWidth,
            screenshotImage: screenshotImage,
            fillImage: fillImage,
            defaultDeviceBodyColor: defaultDeviceBodyColor,
            deviceModelRenderingMode: deviceModelRenderingMode,
            cachedSvgImage: cachedSvgImage,
            allowSynchronousSvgRender: allowSynchronousSvgRender,
            showsEditorHelpers: showsEditorHelpers,
            isEditingText: isEditingText,
            editingTextValue: $editingTextValue,
            editingRichTextData: $editingRichTextData,
            isDropTargeted: $isDropTargeted,
            onRequestImagePicker: { isPickerPresented = true },
            onHandleDrop: handleDrop,
            onCommitTextEdit: commitTextEdit,
            onRichTextChange: { rtfData, plainText in
                editingRichTextData = rtfData
                editingTextValue = plainText
            },
            onSelectionChange: { attrs, range in
                selectionState = RichTextSelectionState(from: attrs, hasRangeSelection: range != nil)
            },
            formatController: formatController,
            resolveNSFont: resolvedNSFont,
            fontWeightResolver: fontWeight,
            renderSvgImage: Self.svgImage
        )
    }

    private var hoverOverlay: some View {
        borderOverlay(opacity: 0.5, lineWidth: 1)
    }

    private func borderOverlay(opacity: Double, lineWidth: CGFloat) -> some View {
        Rectangle()
            .strokeBorder(Color.accentColor.opacity(opacity), lineWidth: lineWidth / zoom)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(currentRotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
            .allowsHitTesting(false)
    }

    private func snapToDisplayPixel(_ value: CGFloat) -> CGFloat {
        (value / displayPixelStep).rounded() * displayPixelStep
    }
}
