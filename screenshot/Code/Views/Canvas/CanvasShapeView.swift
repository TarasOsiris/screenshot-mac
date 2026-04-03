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
    var onCopyTextStyle: (() -> Void)?
    var onPasteTextStyle: (() -> Void)?
    var availableFontFamilies: Set<String> = []
    /// When multi-selected with same-type shapes, applies update to all selected shapes
    var onUpdateSelected: ((@escaping (inout CanvasShapeModel) -> Void) -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onAlignSelected: ((AppState.ShapeAlignment) -> Void)?
    var onDuplicateToAll: (() -> Void)?

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
                        (inside ? NSCursor.openHand : NSCursor.arrow).set()
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
            isDropTargeted: $isDropTargeted,
            onRequestImagePicker: { isPickerPresented = true },
            onHandleDrop: handleDrop,
            onCommitTextEdit: commitTextEdit,
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
            onMatchDeviceSizes: onMatchDeviceSizes,
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
            onDuplicateToAll: onDuplicateToAll
        )
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
            rotationDelta: $rotationDelta,
            resizeState: $resizeState,
            onUpdate: onUpdate
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
        var updated = shape
        updated.text = editingTextValue
        onUpdate(updated)
    }

    /// The custom font family name, if the shape specifies one that's available.
    private var customFontName: String? {
        guard let name = shape.fontName, !name.isEmpty,
              availableFontFamilies.contains(name) else { return nil }
        return name
    }

    private func resolvedNSFont(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont {
        let customName = customFontName
        let cacheKey = "\(customName ?? "__system__")|\(size)|\(weight.rawValue)|\(italic)" as NSString
        if let cached = Self.fontCache.object(forKey: cacheKey) {
            return cached
        }

        let baseFont: NSFont
        if let name = customName {
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
        let resolved = italicized(baseFont, italic: italic)
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

private struct CanvasShapeRenderContent: View {
    let shape: CanvasShapeModel
    let effectiveW: CGFloat
    let effectiveH: CGFloat
    let displayW: CGFloat
    let displayH: CGFloat
    let displayScale: CGFloat
    let displayOutlineWidth: CGFloat
    var screenshotImage: NSImage?
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color
    var deviceModelRenderingMode: DeviceModelRenderingMode
    var cachedSvgImage: NSImage?
    let showsEditorHelpers: Bool
    let isEditingText: Bool
    @Binding var editingTextValue: String
    @Binding var isDropTargeted: Bool
    let onRequestImagePicker: () -> Void
    let onHandleDrop: ([NSItemProvider]) -> Bool
    let onCommitTextEdit: () -> Void
    let resolveNSFont: (CGFloat, NSFont.Weight, Bool) -> NSFont
    let fontWeightResolver: (Int) -> Font.Weight
    let renderSvgImage: (String, Bool, Color, CGSize?) -> NSImage?

    var body: some View {
        switch shape.type {
        case .rectangle:
            let maxRadius = min(displayW, displayH) / 2
            let clampedRadius = min(shape.borderRadius * displayScale, maxRadius)
            outlinedShape(RoundedRectangle(cornerRadius: clampedRadius, style: .circular))

        case .circle:
            outlinedShape(Ellipse())

        case .star:
            outlinedShape(StarShape(pointCount: shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount))

        case .text:
            if isEditingText {
                textEditor
            } else {
                displayTextContent
            }

        case .image:
            imageContent

        case .svg:
            svgContent

        case .device:
            deviceContent
        }
    }

    private var displayTextContent: some View {
        let rawText = shape.text ?? ""
        let showPlaceholder = showsEditorHelpers && rawText.isEmpty
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = fontWeightResolver(shape.fontWeight ?? 700)
        let isItalic = showPlaceholder ? true : (shape.italic ?? false)
        let nsFont = resolveNSFont(fontSize, weight.nsWeight, isItalic)
        let displayText = showPlaceholder ? "Text" : rawText
        let nsColor = NSColor(shape.color.opacity(showPlaceholder ? 0.4 : 1.0))
        let align = shape.textAlign.nsTextAlignment
        let verticalAlign = shape.textVerticalAlign ?? .center
        let uppercase = shape.uppercase ?? false

        return Group {
            if showsEditorHelpers {
                LiveDisplayTextView(
                    text: displayText,
                    font: nsFont,
                    color: nsColor,
                    alignment: align,
                    verticalAlignment: verticalAlign,
                    uppercase: uppercase,
                    letterSpacing: shape.letterSpacing,
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing
                )
            } else {
                RasterizedDisplayTextView(
                    text: displayText,
                    font: nsFont,
                    color: nsColor,
                    alignment: align,
                    verticalAlignment: verticalAlign,
                    uppercase: uppercase,
                    letterSpacing: shape.letterSpacing,
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing
                )
            }
        }
        .frame(width: effectiveW, height: effectiveH)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let screenshotImage {
            Image(nsImage: screenshotImage)
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
    }

    @ViewBuilder
    private var svgContent: some View {
        if let image = cachedSvgImage ?? renderSvgImage(
            shape.svgContent ?? "",
            shape.svgUseColor == true,
            shape.color,
            CGSize(width: effectiveW, height: effectiveH)
        ) {
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
    }

    @ViewBuilder
    private var deviceContent: some View {
        let isInvisible = shape.deviceCategory == .invisible
        let frame = DeviceFrameView(
            category: shape.deviceCategory ?? .iphone,
            bodyColor: shape.resolvedDeviceBodyColor(default: defaultDeviceBodyColor),
            width: displayW,
            height: displayH,
            screenshotImage: screenshotImage,
            deviceFrameId: shape.deviceFrameId,
            devicePitch: shape.resolvedDevicePitch,
            deviceYaw: shape.resolvedDeviceYaw,
            modelRenderingMode: deviceModelRenderingMode,
            invisibleCornerRadius: isInvisible ? shape.borderRadius * displayScale : 0,
            invisibleOutlineWidth: isInvisible ? max(0, (shape.outlineWidth ?? 0) * displayScale) : 0,
            invisibleOutlineColor: isInvisible ? (shape.outlineColor ?? CanvasShapeModel.defaultOutlineColor) : .black
        )

        if screenshotImage == nil && showsEditorHelpers {
            imageDropPlaceholder { frame }
        } else if showsEditorHelpers {
            frame
                .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                    onHandleDrop(providers)
                }
        } else {
            frame
        }
    }

    private var textEditor: some View {
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = fontWeightResolver(shape.fontWeight ?? 700)
        let nsFont = resolveNSFont(fontSize, weight.nsWeight, shape.italic ?? false)

        return InlineTextEditor(
            text: $editingTextValue,
            font: nsFont,
            color: NSColor(shape.color),
            alignment: shape.textAlign.nsTextAlignment,
            verticalAlignment: shape.textVerticalAlign ?? .center,
            uppercase: shape.uppercase ?? false,
            letterSpacing: shape.letterSpacing,
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            onCommit: onCommitTextEdit
        )
        .frame(width: effectiveW, height: effectiveH)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    @ViewBuilder
    private func imageDropPlaceholder<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        let sizeRef = min(displayW, displayH)
        let iconSize = min(28, max(14, sizeRef * 0.18))
        let padding = min(12, max(4, sizeRef * 0.05))
        let cornerRadius = min(8, max(4, sizeRef * 0.04))

        ZStack {
            background()

            Button(action: onRequestImagePicker) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.primary)
                    .padding(padding)
                    .background(
                        .thinMaterial.opacity(isDropTargeted ? 0.9 : 1.0),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
            }
        }
        .frame(width: displayW, height: displayH)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            onHandleDrop(providers)
        }
    }

    @ViewBuilder
    private func outlinedShape<S: InsettableShape>(_ outline: S) -> some View {
        let maxInset = max(0, min(displayW, displayH) / 2)
        let inset = min(displayOutlineWidth, maxInset)

        if let outlineColor = shape.outlineColor, inset > 0 {
            ZStack {
                outline.fill(outlineColor)
                filledShape(outline.inset(by: inset))
            }
            .clipShape(outline)
        } else {
            filledShape(outline)
        }
    }

    @ViewBuilder
    private func filledShape<S: Shape>(_ outline: S) -> some View {
        if shape.resolvedFillStyle == .color {
            outline.fill(shape.color)
        } else {
            shape.fillView(image: fillImage, modelSize: CGSize(width: shape.width, height: shape.height))
                .clipShape(outline)
        }
    }
}

private struct CanvasShapeContextMenuContent: View {
    let shape: CanvasShapeModel
    var isMultiSelected: Bool = false
    var screenshotImage: NSImage?
    @Binding var isPickerPresented: Bool
    var onClearImage: (() -> Void)?
    var onMatchDeviceSizes: (() -> Void)?
    var onTranslate: (() -> Void)?
    var translateLocaleName: String?
    var onCopyTextStyle: (() -> Void)?
    var onPasteTextStyle: (() -> Void)?
    let applyUpdate: (@escaping (inout CanvasShapeModel) -> Void) -> Void
    let deleteAction: () -> Void
    var onAlignSelected: ((AppState.ShapeAlignment) -> Void)?
    var onDuplicateToAll: (() -> Void)?

    var body: some View {
        if !isMultiSelected {
            if shape.type == .device || shape.type == .image {
                Button("Replace Image...") {
                    isPickerPresented = true
                }
                Button("Reset Image") {
                    onClearImage?()
                }
                .disabled(shape.displayImageFileName == nil)
                if shape.type == .image, let screenshotImage {
                    Button("Restore Original Aspect Ratio") {
                        let imageSize = screenshotImage.size
                        guard imageSize.width > 0 && imageSize.height > 0 else { return }
                        let newHeight = shape.width / (imageSize.width / imageSize.height)
                        applyUpdate { $0.height = newHeight }
                    }
                }
                Divider()
            }

            if shape.type == .device {
                Menu("Change Device") {
                    DeviceMenuContent(
                        onSelectCategory: { category in
                            applyUpdate { $0.selectAbstractDevice(category, screenshotImageSize: screenshotImage?.size) }
                        },
                        onSelectFrame: { frame in
                            applyUpdate { $0.selectRealFrame(frame) }
                        },
                        selectedCategory: shape.deviceCategory,
                        selectedFrameId: shape.deviceFrameId
                    )
                }
                if let onMatchDeviceSizes {
                    Button("Resize to Fit All Devices", action: onMatchDeviceSizes)
                }
                Divider()
            }
        }

        if shape.type == .text {
            Picker("Align", selection: Binding(
                get: { shape.textAlign ?? .center },
                set: { value in applyUpdate { $0.textAlign = value } }
            )) {
                Label("Left", systemImage: "text.alignleft").tag(TextAlign.left)
                Label("Center", systemImage: "text.aligncenter").tag(TextAlign.center)
                Label("Right", systemImage: "text.alignright").tag(TextAlign.right)
            }
            Toggle("Italic", isOn: Binding(
                get: { shape.italic ?? false },
                set: { value in applyUpdate { $0.italic = value } }
            ))
            Toggle("Uppercase", isOn: Binding(
                get: { shape.uppercase ?? false },
                set: { value in applyUpdate { $0.uppercase = value } }
            ))
            Menu("Change Font Size") {
                let currentSize = Int(shape.fontSize ?? CanvasShapeModel.defaultFontSize)
                ForEach(CanvasShapeModel.fontSizePresets, id: \.self) { size in
                    Button {
                        applyUpdate { $0.fontSize = CGFloat(size) }
                    } label: {
                        if currentSize == size {
                            Label("\(size)", systemImage: "checkmark")
                        } else {
                            Text("\(size)")
                        }
                    }
                }
            }
            if !isMultiSelected, let onCopyTextStyle {
                Divider()
                Button("Copy Text Style", systemImage: "paintbrush") {
                    onCopyTextStyle()
                }
                Button("Paste Text Style", systemImage: "paintbrush.fill") {
                    onPasteTextStyle?()
                }
                .disabled(onPasteTextStyle == nil)
            }
            if !isMultiSelected, let onTranslate, let translateLocaleName {
                Divider()
                Button("Translate into \(translateLocaleName)", action: onTranslate)
                    .disabled((shape.text ?? "").isEmpty)
            }
            Divider()
        }

        if shape.type == .svg {
            if let svgContent = shape.svgContent,
               let originalSize = SvgHelper.parseViewBoxSize(svgContent) {
                Button("Restore Original Aspect Ratio") {
                    let newHeight = shape.width / (originalSize.width / originalSize.height)
                    applyUpdate { $0.height = newHeight }
                }
            }
            Toggle("Use Custom Color", isOn: Binding(
                get: { shape.svgUseColor ?? false },
                set: { value in applyUpdate { $0.svgUseColor = value } }
            ))
            Divider()
        }

        if shape.type == .star {
            Menu("Points: \(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)") {
                ForEach(3...12, id: \.self) { count in
                    Button("\(count)") {
                        applyUpdate { $0.starPointCount = count }
                    }
                }
            }
            Divider()
        }

        Toggle("Clip to Frame", isOn: Binding(
            get: { shape.clipToTemplate ?? false },
            set: { value in applyUpdate { $0.clipToTemplate = value } }
        ))

        if let onDuplicateToAll {
            Button("Duplicate to All Screenshots") {
                onDuplicateToAll()
            }
        }

        if let onAlignSelected {
            Divider()
            Menu("Align Selected") {
                Button("Align Left") { onAlignSelected(.left) }
                Button("Align Center") { onAlignSelected(.centerH) }
                Button("Align Right") { onAlignSelected(.right) }
                Divider()
                Button("Align Top") { onAlignSelected(.top) }
                Button("Align Middle") { onAlignSelected(.centerV) }
                Button("Align Bottom") { onAlignSelected(.bottom) }
                Divider()
                Button("Distribute Horizontally") { onAlignSelected(.distributeH) }
                Button("Distribute Vertically") { onAlignSelected(.distributeV) }
            }
        }

        Divider()

        Button(isMultiSelected ? "Delete Selected" : "Delete", role: .destructive, action: deleteAction)
    }
}

private struct CanvasShapeHandlesOverlay: View {
    let shape: CanvasShapeModel
    let displayScale: CGFloat
    let zoom: CGFloat
    let displayX: CGFloat
    let displayY: CGFloat
    let displayW: CGFloat
    let displayH: CGFloat
    let currentRotation: Double
    let handleDiameter: CGFloat
    @Binding var rotationDelta: Double
    @Binding var resizeState: ResizeState?
    let onUpdate: (CanvasShapeModel) -> Void

    var body: some View {
        selectionOverlay
        resizeHandles
    }

    private var rotationRadians: CGFloat { shape.rotation * .pi / 180 }

    private var selectionOverlay: some View {
        Rectangle()
            .strokeBorder(Color.accentColor.opacity(1.0), lineWidth: 1.5 / zoom)
            .frame(width: displayW, height: displayH)
            .rotationEffect(.degrees(currentRotation))
            .position(x: displayX + displayW / 2, y: displayY + displayH / 2)
            .allowsHitTesting(false)
    }

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

    private var rotateHandleContent: some View {
        let stemLength: CGFloat = 24 / zoom
        let handleSize: CGFloat = 10 / zoom
        let hitSize: CGFloat = 24 / zoom

        return ZStack {
            Path { path in
                path.move(to: CGPoint(x: displayW / 2, y: -handleDiameter / (2 * zoom)))
                path.addLine(to: CGPoint(x: displayW / 2, y: -stemLength))
            }
            .stroke(Color.accentColor, lineWidth: 1 / zoom)

            ZStack {
                Color.clear
                    .frame(width: hitSize, height: hitSize)
                    .contentShape(Rectangle())

                Circle()
                    .fill(Color.white)
                    .frame(width: handleSize, height: handleSize)

                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom)
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

    private func rotateGesture(stemLength: CGFloat) -> some Gesture {
        let handleDistance = (displayH / 2 + stemLength) * zoom
        let baseAngleRadians = (shape.rotation - 90) * .pi / 180
        let handleVectorX = handleDistance * cos(baseAngleRadians)
        let handleVectorY = handleDistance * sin(baseAngleRadians)
        let startAngle = atan2(handleVectorY, handleVectorX) * 180 / .pi

        return DragGesture(coordinateSpace: .global)
            .onChanged { value in
                CursorHelper.rotateCursor.set()

                let currentX = handleVectorX + value.translation.width
                let currentY = handleVectorY + value.translation.height
                let currentAngle = atan2(currentY, currentX) * 180 / .pi

                var delta = currentAngle - startAngle
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
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        return normalized
    }

    private func handlePosition(for edge: ResizeEdge) -> CGPoint {
        let halfWidth = displayW / 2
        let halfHeight = displayH / 2
        switch edge {
        case .topLeft: return CGPoint(x: 0, y: 0)
        case .top: return CGPoint(x: halfWidth, y: 0)
        case .topRight: return CGPoint(x: displayW, y: 0)
        case .left: return CGPoint(x: 0, y: halfHeight)
        case .right: return CGPoint(x: displayW, y: halfHeight)
        case .bottomLeft: return CGPoint(x: 0, y: displayH)
        case .bottom: return CGPoint(x: halfWidth, y: displayH)
        case .bottomRight: return CGPoint(x: displayW, y: displayH)
        }
    }

    private func resizeHandle(edge: ResizeEdge) -> some View {
        let handleSize = handleDiameter / zoom
        let hitSize: CGFloat = 20 / zoom
        let position = handlePosition(for: edge)

        return ZStack {
            Color.clear
                .frame(width: hitSize, height: hitSize)
                .contentShape(Rectangle())

            Circle()
                .fill(Color.white)
                .strokeBorder(Color.accentColor, lineWidth: 1.5 / zoom)
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
        .position(position)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    let effectiveScale = displayScale * zoom
                    let tx = value.translation.width / effectiveScale
                    let ty = value.translation.height / effectiveScale
                    let lockAspectRatio = NSEvent.modifierFlags.contains(.shift) || (shape.type == .device && shape.deviceCategory != .invisible)
                    resizeState = computeResize(edge: edge, tx: tx, ty: ty, lockAspectRatio: lockAspectRatio)
                }
                .onEnded { _ in
                    if let resizeState {
                        var updated = shape
                        updated.x = resizeState.newX
                        updated.y = resizeState.newY
                        updated.width = resizeState.newW
                        updated.height = resizeState.newH
                        onUpdate(updated)
                    }
                    resizeState = nil
                }
        )
    }

    private func computeResize(edge: ResizeEdge, tx: CGFloat, ty: CGFloat, lockAspectRatio: Bool) -> ResizeState {
        let minSize: CGFloat = shape.type == .device ? CanvasShapeModel.deviceMinSize : 20
        let cosA = cos(rotationRadians)
        let sinA = sin(rotationRadians)
        let localTx = tx * cosA + ty * sinA
        let localTy = -tx * sinA + ty * cosA

        var newW = shape.width
        var newH = shape.height
        switch edge {
        case .topLeft:
            newW = max(minSize, shape.width - localTx)
            newH = max(minSize, shape.height - localTy)
        case .top:
            newH = max(minSize, shape.height - localTy)
        case .topRight:
            newW = max(minSize, shape.width + localTx)
            newH = max(minSize, shape.height - localTy)
        case .left:
            newW = max(minSize, shape.width - localTx)
        case .right:
            newW = max(minSize, shape.width + localTx)
        case .bottomLeft:
            newW = max(minSize, shape.width - localTx)
            newH = max(minSize, shape.height + localTy)
        case .bottom:
            newH = max(minSize, shape.height + localTy)
        case .bottomRight:
            newW = max(minSize, shape.width + localTx)
            newH = max(minSize, shape.height + localTy)
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

        let anchor = edge.anchorPoint(width: shape.width, height: shape.height)
        let centerX = shape.x + shape.width / 2
        let centerY = shape.y + shape.height / 2
        let anchorX = anchor.x - shape.width / 2
        let anchorY = anchor.y - shape.height / 2
        let anchorCanvasX = centerX + anchorX * cosA - anchorY * sinA
        let anchorCanvasY = centerY + anchorX * sinA + anchorY * cosA

        let newAnchor = edge.anchorPoint(width: newW, height: newH)
        let newAnchorX = newAnchor.x - newW / 2
        let newAnchorY = newAnchor.y - newH / 2
        let newCenterX = anchorCanvasX - (newAnchorX * cosA - newAnchorY * sinA)
        let newCenterY = anchorCanvasY - (newAnchorX * sinA + newAnchorY * cosA)

        return ResizeState(
            newX: newCenterX - newW / 2,
            newY: newCenterY - newH / 2,
            newW: newW,
            newH: newH
        )
    }
}
