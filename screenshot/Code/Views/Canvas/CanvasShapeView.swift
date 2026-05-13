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
    private static let fontCache: NSCache<NSString, NSFont> = {
        let cache = NSCache<NSString, NSFont>()
        cache.countLimit = 200
        return cache
    }()

    @Environment(\.displayScale) private var screenScale

    let shape: CanvasShapeModel
    let displayScale: CGFloat
    var zoom: CGFloat = 1.0
    let isSelected: Bool
    var isMultiSelected: Bool = false
    var screenshotImage: NSImage?
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color = CanvasShapeModel.defaultDeviceBodyColor
    var groupDragOffset: CGSize = .zero
    var deviceModelRenderingMode: DeviceModelRenderingMode = .snapshot

    var clipBounds: CGRect?
    var canvasGlobalOrigin: CGPoint = .zero
    var showsEditorHelpers: Bool = true
    /// In-progress resize/rotation reported by the selection overlay so this
    /// view can render the shape at the pending size/angle during the drag.
    var resizeState: ResizeState?
    var rotationDelta: Double = 0
    var onSelect: () -> Void
    var onShiftSelect: (() -> Void)?
    var onUpdate: (CanvasShapeModel) -> Void
    var onDelete: () -> Void
    var onScreenshotDrop: ((NSImage) -> Void)?
    var onClearImage: (() -> Void)?
    var onRemoveBackground: (() -> Void)?
    var onCaptureSimulator: (() -> Void)?
    var onDragSnap: ((CanvasShapeModel, CGSize) -> SnapResult)?
    var onDragEnd: (() -> Void)?
    var onOptionDragDuplicate: ((UUID) -> UUID?)?
    var onDragProgress: ((CGSize) -> Void)?
    var onGroupDragEnd: ((CGSize) -> Void)?
    var onDidAppearAfterAdd: (() -> Void)?
    var onEditingTextChanged: ((Bool) -> Void)?
    var onFormatBarStateChanged: ((RichTextSelectionState?, RichTextFormatController?) -> Void)?
    var onFormatBarAnchorChanged: ((CGPoint?) -> Void)?
    var onMatchDeviceSizes: (() -> Void)?
    var onMatchSelectedDeviceSizes: (() -> Void)?
    var onTranslate: (() -> Void)?
    var translateLocaleName: String?
    var onCopyTextStyle: (() -> Void)?
    var onPasteTextStyle: (() -> Void)?
    var availableFontFamilies: Set<String> = []
    /// When multi-selected with same-type shapes, applies update to all selected shapes
    var onUpdateSelected: ((@escaping (inout CanvasShapeModel) -> Void) -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onAlignSelected: ((AppState.ShapeAlignment) -> Void)?
    var onDuplicateToTemplates: ((AppState.DuplicateDirection) -> Void)?
    var onToggleLock: (() -> Void)?
    var lockToggleWillUnlock: Bool = false

    @State private var addBumpScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovered = false
    @State private var localResizeState: ResizeState?
    @State private var isDropTargeted = false
    @State private var isPickerPresented = false
    @State private var isEditingText = false
    @State private var editingTextValue = ""
    @State private var editingRichTextData: String?
    @State private var selectionState: RichTextSelectionState?
    @StateObject private var formatController = RichTextFormatController()
    @State private var cachedSvgImage: NSImage?
    @State private var svgCacheKey = ""
    @State private var localRotationDelta: Double = 0
    @State private var svgResizeDebounceTask: Task<Void, Never>?

    private let handleDiameter: CGFloat = 8
    private var displayPixelStep: CGFloat { 1 / max(screenScale, 1) }
    private var activeResizeState: ResizeState? { isMultiSelected ? resizeState : localResizeState }
    private var activeRotationDelta: Double { isMultiSelected ? rotationDelta : localRotationDelta }

    // Current effective geometry (accounts for in-progress resize or drag)
    private var effectiveX: CGFloat {
        if let rs = activeResizeState { return rs.newX } else { return shape.x + dragOffset.width + groupDragOffset.width }
    }
    private var effectiveY: CGFloat {
        if let rs = activeResizeState { return rs.newY } else { return shape.y + dragOffset.height + groupDragOffset.height }
    }
    private var effectiveW: CGFloat { activeResizeState?.newW ?? shape.width }
    private var effectiveH: CGFloat { activeResizeState?.newH ?? shape.height }

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
        isEditingText ? 0 : shape.rotation + activeRotationDelta
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
                if editing {
                    updateFormatBarAnchor()
                }
            }
            .onChange(of: selectionState) { _, newState in
                if isEditingText {
                    onFormatBarStateChanged?(newState, formatController)
                }
            }
            .onChange(of: canvasGlobalOrigin) { if isEditingText { updateFormatBarAnchor() } }
            .onChange(of: displayRect) { if isEditingText { updateFormatBarAnchor() } }
            .onChange(of: zoom) { if isEditingText { updateFormatBarAnchor() } }
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
            ZStack(alignment: .topLeading) {
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
                            guard !shape.resolvedIsLocked else {
                                onSelect()
                                return
                            }
                            if shape.type == .text {
                                editingTextValue = shape.text ?? ""
                                editingRichTextData = shape.richText
                                formatController.resetRichTextSession()
                                if shape.richText != nil {
                                    formatController.beginRichTextSession()
                                }
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

                if isSelected && !isMultiSelected {
                    handlesContent
                        .zIndex(99)
                }
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
                        let cursor: NSCursor = (inside && !shape.resolvedIsLocked) ? .openHand : .arrow
                        cursor.set()
                    }
                }
            case .ended:
                if isHovered {
                    isHovered = false
                    if showsEditorHelpers && isSelected && !isDragging {
                        NSCursor.arrow.set()
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

    /// Applies an update to this shape, or to all selected shapes if multi-selected with same type
    private func applyUpdate(_ update: @escaping (inout CanvasShapeModel) -> Void) {
        if let onUpdateSelected {
            onUpdateSelected(update)
        } else {
            var updated = shape
            update(&updated)
            onUpdate(updated)
        }
    }

    @ViewBuilder
    private var shapeContextMenu: some View {
        CanvasShapeContextMenuContent(
            shape: shape,
            isMultiSelected: isMultiSelected,
            screenshotImage: screenshotImage,
            isPickerPresented: $isPickerPresented,
            onClearImage: onClearImage,
            onRemoveBackground: onRemoveBackground,
            onCaptureSimulator: onCaptureSimulator,
            onMatchDeviceSizes: onMatchDeviceSizes,
            onMatchSelectedDeviceSizes: onMatchSelectedDeviceSizes,
            onTranslate: onTranslate,
            translateLocaleName: translateLocaleName,
            onCopyTextStyle: onCopyTextStyle,
            onPasteTextStyle: onPasteTextStyle,
            applyUpdate: applyUpdate,
            deleteAction: {
                if let onDeleteSelected {
                    onDeleteSelected()
                } else {
                    onDelete()
                }
            },
            onAlignSelected: onAlignSelected,
            onDuplicateToTemplates: onDuplicateToTemplates,
            onToggleLock: onToggleLock,
            lockToggleWillUnlock: lockToggleWillUnlock
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

    @ViewBuilder
    private var handlesContent: some View {
        CanvasShapeHandlesOverlay(
            shape: shape,
            displayScale: displayScale,
            zoom: zoom,
            displayX: displayX,
            displayY: displayY,
            displayW: displayW,
            displayH: displayH,
            currentRotation: currentRotation,
            handleDiameter: handleDiameter,
            rotationDelta: $localRotationDelta,
            resizeState: $localResizeState,
            onUpdate: onUpdate
        )
    }

    private func snapToDisplayPixel(_ value: CGFloat) -> CGFloat {
        (value / displayPixelStep).rounded() * displayPixelStep
    }

    // MARK: - Drag

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !shape.resolvedIsLocked else {
                    if !isDragging && !isMultiSelected {
                        onSelect()
                    }
                    return
                }
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
                // Report drag progress so the selection overlay (which lives
                // outside the shape) can keep its handles in sync.
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

    nonisolated static func svgImage(from svgContent: String, useColor: Bool, color: Color, targetSize: CGSize? = nil) -> NSImage? {
        SvgHelper.renderImage(from: svgContent, useColor: useColor, color: color, targetSize: targetSize)
    }

    private func commitTextEdit() {
        guard isEditingText else { return }
        isEditingText = false
        selectionState = nil
        var updated = shape
        updated.text = editingTextValue
        updated.richText = editingRichTextData
        if updated.text?.isEmpty != false {
            updated.richText = nil
        }
        formatController.resetRichTextSession()
        onUpdate(updated)
    }

    private func updateFormatBarAnchor() {
        onFormatBarAnchorChanged?(CGPoint(
            x: canvasGlobalOrigin.x + ((displayX + displayW / 2) * zoom),
            y: canvasGlobalOrigin.y + (displayY * zoom) - 10
        ))
    }

    private var customFontName: String? {
        guard let name = shape.fontName, !name.isEmpty else { return nil }
        // Custom-font display names ("Playfair Display Italic") aren't in NSFontManager's
        // family list; the registry is the authoritative check for them. Fall back to the
        // passed-in family set for system fonts.
        if CustomFontRegistry.font(forDisplayName: name) != nil { return name }
        if availableFontFamilies.contains(name) { return name }
        return nil
    }

    private func resolvedNSFont(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont {
        let customName = customFontName
        let cacheKey = "\(customName ?? "__system__")|\(size)|\(weight.rawValue)|\(italic)" as NSString
        if let cached = Self.fontCache.object(forKey: cacheKey) {
            return cached
        }

        let resolved: NSFont
        if let name = customName {
            resolved = CustomFontRegistry.resolveNSFont(
                name: name,
                size: size,
                managerWeight: Self.fontManagerWeight(for: weight),
                italic: italic
            )
        } else {
            resolved = italicized(NSFont.systemFont(ofSize: size, weight: weight), italic: italic)
        }
        Self.fontCache.setObject(resolved, forKey: cacheKey)
        return resolved
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
