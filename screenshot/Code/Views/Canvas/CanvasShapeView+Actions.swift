import Foundation
import SwiftUI

extension CanvasShapeView {
    @ViewBuilder
    var shapeContextMenu: some View {
        CanvasShapeContextMenuContent(
            shape: shape,
            isMultiSelected: isMultiSelected,
            screenshotImage: screenshotImage,
            isPickerPresented: $isPickerPresented,
            onClearImage: interactions.onClearImage,
            onRemoveBackground: interactions.onRemoveBackground,
            onCaptureSimulator: interactions.onCaptureSimulator,
            onMatchDeviceSizes: interactions.onMatchDeviceSizes,
            onMatchSelectedDeviceSizes: interactions.onMatchSelectedDeviceSizes,
            onCenterShape: interactions.onCenterShape,
            onTranslate: interactions.onTranslate,
            translateLocaleName: interactions.translateLocaleName,
            onTranslateAllLocales: interactions.onTranslateAllLocales,
            translateAllLocalesDisabled: interactions.translateAllLocalesDisabled,
            onResetAllTranslations: interactions.onResetAllTranslations,
            resetAllTranslationsDisabled: interactions.resetAllTranslationsDisabled,
            reuseTranslationTargets: interactions.reuseTranslationTargets,
            onLinkTranslation: interactions.onLinkTranslation,
            onUnlinkTranslation: interactions.onUnlinkTranslation,
            nonBaseLocaleCount: interactions.nonBaseLocaleCount,
            onCopyTextStyle: interactions.onCopyTextStyle,
            onPasteTextStyle: interactions.onPasteTextStyle,
            applyUpdate: applyUpdate,
            deleteAction: {
                if let onDeleteSelected = interactions.onDeleteSelected {
                    onDeleteSelected()
                } else {
                    interactions.onDelete()
                }
            },
            onAlignSelected: interactions.onAlignSelected,
            onMatchGeometryToThis: interactions.onMatchGeometryToThis,
            onDuplicateToTemplates: interactions.onDuplicateToTemplates,
            onToggleLock: interactions.onToggleLock,
            lockToggleWillUnlock: interactions.lockToggleWillUnlock
        )
    }

    private func applyUpdate(_ update: @escaping (inout CanvasShapeModel) -> Void) {
        if let onUpdateSelected = interactions.onUpdateSelected {
            onUpdateSelected(update)
        } else {
            var updated = shape
            update(&updated)
            interactions.onUpdate(updated)
        }
    }
}

// MARK: - Lifecycle and selection

extension CanvasShapeView {
    func handleAppear() {
        updateSvgCache()
        guard let onDidAppearAfterAdd = interactions.onDidAppearAfterAdd else { return }
        withAnimation(.easeOut(duration: 0.08)) {
            addBumpScale = 1.12
        } completion: {
            withAnimation(.easeInOut(duration: 0.08)) {
                addBumpScale = 1.0
            }
        }
        onDidAppearAfterAdd()
    }

    func handleEditingStateChange(_ editing: Bool) {
        interactions.onEditingTextChanged?(editing)
        if editing {
            interactions.onInlineTextEditChanged?(
                shape.id,
                { (editingTextValue, editingRichTextData) },
                { endTextEditingAfterExternalCommit() }
            )
        } else {
            interactions.onInlineTextEditChanged?(shape.id, nil, nil)
        }
    }

    func handleSelectionStateChange(_ newState: RichTextSelectionState?) {
        guard isEditingText else { return }
        interactions.onFormatBarStateChanged?(newState, formatController)
    }

    func handleSelectionChange(_ selected: Bool) {
        if !selected && isEditingText {
            commitTextEdit()
        }
    }

    func handleDisappear() {
        guard isEditingText else { return }
        commitTextEdit()
        // `.onChange(of: isEditingText)` is not reliably delivered during view teardown.
        interactions.onInlineTextEditChanged?(shape.id, nil, nil)
        interactions.onEditingTextChanged?(false)
    }

    func handleDoubleTap() {
        guard !shape.resolvedIsLocked else {
            interactions.onSelect()
            return
        }
        if shape.type == .text {
            beginTextEditing()
        } else if shape.type == .device || shape.type == .image {
            isPickerPresented = true
        }
    }

    private func beginTextEditing() {
        editingTextValue = shape.text ?? ""
        editingRichTextData = shape.richText
        formatController.resetRichTextSession()
        if shape.richText != nil {
            formatController.beginRichTextSession()
        }
        isEditingText = true
        // Publish immediately so Cmd+Z can reach this editor's undo manager from the first keystroke.
        interactions.onFormatBarStateChanged?(nil, formatController)
        interactions.onSelect()
    }

    func handleTap() {
        if PlatformModifiers.shiftDown {
            interactions.onShiftSelect?()
        } else {
            interactions.onSelect()
        }
    }
}

// MARK: - Drag and drop

extension CanvasShapeView {
    var dragGesture: some Gesture {
        DragGesture()
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !shape.resolvedIsLocked else {
            if !isDragging && !isMultiSelected {
                interactions.onSelect()
            }
            return
        }
        if !isDragging {
            beginDrag()
        }
        let rawOffset = CGSize(
            width: value.translation.width / displayScale,
            height: value.translation.height / displayScale
        )
        if let snap = interactions.onDragSnap?(shape, rawOffset) {
            dragOffset = snap.snappedOffset
        } else {
            dragOffset = rawOffset
        }
        // Report progress for single- and multi-select alike so the lifted
        // selection layer's handles track the shape during the drag.
        interactions.onDragProgress?(dragOffset)
    }

    private func beginDrag() {
        isDragging = true
        PlatformCursor.setClosedHand()

        if PlatformModifiers.optionDown {
            _ = interactions.onOptionDragDuplicate?(shape.id)
        }

        if !isMultiSelected {
            interactions.onSelect()
        }
    }

    private func handleDragEnded(_: DragGesture.Value) {
        PlatformCursor.setArrow()
        let finalOffset = dragOffset
        dragOffset = .zero
        isDragging = false
        if isMultiSelected {
            interactions.onGroupDragEnd?(finalOffset)
        } else {
            var updated = shape
            updated.x += finalOffset.width
            updated.y += finalOffset.height
            interactions.onUpdate(updated)
        }
        interactions.onDragEnd?()
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSImage.self) { image, _ in
            if let image = image as? NSImage {
                DispatchQueue.main.async {
                    interactions.onScreenshotDrop?(image)
                }
            }
        }
        return true
    }
}

// MARK: - SVG and text editing

extension CanvasShapeView {
    func debounceSvgCacheUpdate() {
        svgResizeDebounceTask?.cancel()
        svgResizeDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            updateSvgCache()
        }
    }

    func updateSvgCache() {
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

    func commitTextEdit() {
        guard isEditingText else { return }
        isEditingText = false
        selectionState = nil
        formatController.resetRichTextSession()
        // AppState merges the text onto the live base shape under the current locale.
        interactions.onCommitInlineText?(editingTextValue, editingRichTextData)
    }

    private func endTextEditingAfterExternalCommit() {
        guard isEditingText else { return }
        isEditingText = false
        selectionState = nil
        formatController.resetRichTextSession()
        interactions.onInlineTextEditChanged?(shape.id, nil, nil)
        interactions.onEditingTextChanged?(false)
    }

    @ViewBuilder
    var formatBarAnchorReader: some View {
        #if os(macOS)
        if isEditingText {
            Color.clear
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    interactions.onFormatBarAnchorChanged?(CGPoint(x: frame.midX, y: frame.minY - 10))
                }
        }
        #endif
    }
}

// MARK: - Font resolution

extension CanvasShapeView {
    func resolvedNSFont(size: CGFloat, weight: NSFont.Weight, italic: Bool = false) -> NSFont {
        CanvasShapeFontResolver.resolvedFont(
            shape: shape,
            availableFontFamilies: availableFontFamilies,
            size: size,
            weight: weight,
            italic: italic
        )
    }

    func fontWeight(_ weight: Int) -> Font.Weight {
        CanvasShapeFontResolver.fontWeight(weight)
    }
}

private enum CanvasShapeFontResolver {
    private static let fontCache: NSCache<NSString, NSFont> = {
        let cache = NSCache<NSString, NSFont>()
        cache.countLimit = 200
        return cache
    }()

    static func resolvedFont(
        shape: CanvasShapeModel,
        availableFontFamilies: Set<String>,
        size: CGFloat,
        weight: NSFont.Weight,
        italic: Bool = false
    ) -> NSFont {
        let customName = customFontName(for: shape, availableFontFamilies: availableFontFamilies)
        let resolvedCustomFont = customName.map(CustomFontRegistry.resolve)
        let resolvedName = resolvedCustomFont?.exactName ?? resolvedCustomFont?.family ?? "__system__"
        let cacheKey = "\(resolvedName)|\(size)|\(weight.rawValue)|\(italic)" as NSString
        if let cached = fontCache.object(forKey: cacheKey) {
            return cached
        }

        let resolved: NSFont
        if let name = customName {
            resolved = CustomFontRegistry.resolveNSFont(
                name: name,
                size: size,
                managerWeight: fontManagerWeight(for: weight),
                italic: italic
            )
        } else {
            resolved = italicized(NSFont.systemFont(ofSize: size, weight: weight), italic: italic)
        }
        fontCache.setObject(resolved, forKey: cacheKey)
        return resolved
    }

    static func fontWeight(_ weight: Int) -> Font.Weight {
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

    private static func customFontName(for shape: CanvasShapeModel, availableFontFamilies: Set<String>) -> String? {
        guard let name = shape.fontName, !name.isEmpty else { return nil }
        if CustomFontRegistry.font(forDisplayName: name) != nil { return name }
        if availableFontFamilies.contains(name) { return name }
        return nil
    }

    private static func italicized(_ font: NSFont, italic: Bool) -> NSFont {
        guard italic else { return font }
        #if os(macOS)
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        #else
        return font.addingItalic()
        #endif
    }

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
}
