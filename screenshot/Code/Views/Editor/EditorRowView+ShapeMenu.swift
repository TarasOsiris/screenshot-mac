import SwiftUI

/// The row-wide selection answers the shape context menu needs, computed once per canvas body
/// rather than re-derived for every shape.
struct CanvasSelectionFacts {
    var isNonBaseLocale = false
    var currentLocaleName: String?
    var nonBaseLocaleCount = 0
    var isMultiSelection = false
    var selectionFullyLocked = false
    var allSelectedSameType = false
    var selectedTextShapeIds: Set<UUID> = []
    var allSelectedAreDevices = false
}

extension EditorRowView {
    /// The context menu for one shape, assembled by the row.
    ///
    /// The *actions* live here rather than on `CanvasShapeView` so they are not ~25 extra closures
    /// on every shape's `CanvasShapeInteractions`. The menu itself is still attached per shape, and
    /// that is not free: SwiftUI materializes a `.contextMenu`'s items into `NSMenuItem`s as part of
    /// building the view, and `PlatformItemListTransformModifier` and friends were over a tenth of a
    /// scrollbar-drag trace.
    ///
    /// One menu per row was tried and reverted. It has to resolve its target from the last hovered
    /// point, and because the items are built with the body rather than on right-click, the menu
    /// showed whatever the point was at the previous body evaluation. Moving it back to the row
    /// needs a menu built *in response to* the click — an on-demand `NSMenu` on macOS.
    func shapeContextMenu(
        for shape: CanvasShapeModel,
        facts: CanvasSelectionFacts
    ) -> CanvasShapeContextMenuContent {
        let isInSelection = selectedShapeIds.contains(shape.id)
        let isMulti = isInSelection && facts.isMultiSelection

        return CanvasShapeContextMenuContent(
            shape: shape,
            isMultiSelected: isMulti,
            screenshotImage: shape.displayImageFileName.flatMap { state.screenshotImages[$0] },
            onRequestImagePicker: { requestImagePicker(for: shape.id) },
            onClearImage: {
                state.clearImage(for: shape.id)
            },
            onRemoveBackground: shape.type == .image ? {
                state.removeImageBackground(for: shape.id) { message in
                    activeAlert = .backgroundRemovalFailed(message)
                }
            } : nil,
            onCaptureSimulator: simulatorCaptureAction(for: shape),
            onMatchDeviceSizes: shape.type == .device ? {
                let matchingIds = Set(row.activeShapes.filter { other in
                    other.id != shape.id &&
                    other.type == .device &&
                    other.deviceCategory == shape.deviceCategory
                }.map(\.id))
                guard !matchingIds.isEmpty else { return }
                state.updateShapes(matchingIds, in: row.id) { other in
                    other.width = shape.width
                    other.height = shape.height
                }
            } : nil,
            onMatchSelectedDeviceSizes: (isMulti && shape.type == .device && facts.allSelectedAreDevices) ? {
                let targetIds = selectedShapeIds.subtracting([shape.id])
                guard !targetIds.isEmpty else { return }
                state.updateShapes(targetIds,
                                   in: row.id,
                                   undoName: "Match Size to Selected Devices") { other in
                    other.width = shape.width
                    other.height = shape.height
                }
            } : nil,
            onCenterShape: { axis in
                let targets: Set<UUID> = (isMulti && selectedShapeIds.contains(shape.id))
                    ? selectedShapeIds : [shape.id]
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.centerShapes(targets, in: row.id, axis: axis)
                }
            },
            onTranslate: (shape.type == .text && facts.isNonBaseLocale) ? {
                state.localeMenu.pendingTranslateShapeId = shape.id
            } : nil,
            translateLocaleName: facts.currentLocaleName,
            onTranslateAllLocales: (shape.type == .text && !facts.isNonBaseLocale && facts.nonBaseLocaleCount > 0) ? {
                let isMultiText = selectedShapeIds.count > 1 && selectedShapeIds.contains(shape.id)
                if isMultiText {
                    let translatableIds: Set<UUID> = Set(
                        row.activeShapes
                            .filter { selectedShapeIds.contains($0.id) && $0.hasTranslatableText }
                            .map(\.id)
                    )
                    guard !translatableIds.isEmpty else { return }
                    state.localeMenu.pendingFanOutTranslateShapeIds = translatableIds
                } else {
                    state.localeMenu.pendingFanOutTranslateShapeIds = [shape.id]
                }
            } : nil,
            translateAllLocalesDisabled: state.localeMenu.isFanOutTranslating,
            onResetAllTranslations: (shape.type == .text && !facts.isNonBaseLocale && facts.nonBaseLocaleCount > 0) ? {
                state.resetAllTranslations(shapeIds: isMulti ? facts.selectedTextShapeIds : [shape.id])
            } : nil,
            resetAllTranslationsDisabled: (shape.type == .text && !facts.isNonBaseLocale && facts.nonBaseLocaleCount > 0)
                ? { !state.anyTranslationOrOverride(shapeIds: isMulti ? facts.selectedTextShapeIds : [shape.id]) }
                : { false },
            reuseTranslationTargets: shape.type == .text ? {
                state.reusableTranslationTargets(excludingShapeId: shape.id)
                    .map { (key: $0.key, label: $0.baseText.singleLineMenuLabel()) }
            } : nil,
            onLinkTranslation: shape.type == .text ? { key in
                state.linkTranslation(shapeId: shape.id, toTargetKey: key)
            } : nil,
            onUnlinkTranslation: shape.type == .text ? {
                state.unlinkTranslation(shapeId: shape.id)
            } : nil,
            nonBaseLocaleCount: facts.nonBaseLocaleCount,
            onCopyTextStyle: shape.type == .text ? {
                state.textStyleClipboard = shape.extractTextStyle()
            } : nil,
            onPasteTextStyle: shape.type == .text && state.textStyleClipboard != nil ? { [rowId = row.id] in
                guard let style = state.textStyleClipboard else { return }
                state.updateShapes([shape.id], in: rowId) { $0.applyTextStyle(style) }
            } : nil,
            applyUpdate: { update in
                if isMulti && facts.allSelectedSameType {
                    state.updateShapes(selectedShapeIds, in: row.id, update: update)
                } else {
                    var updated = shape
                    update(&updated)
                    state.updateShape(updated)
                }
            },
            deleteAction: {
                if isMulti {
                    state.deleteSelectedShapes()
                } else {
                    state.deleteShape(shape.id)
                }
            },
            onAlignSelected: isMulti ? { alignment in
                state.alignSelectedShapes(alignment)
            } : nil,
            onMatchGeometryToThis: isMulti ? { [shapeId = shape.id] mode in
                state.matchShapeGeometry(toSource: shapeId, mode: mode)
            } : nil,
            onDuplicateToTemplates: row.templates.count > 1 ? { [shapeId = shape.id] direction in
                let ids = state.selectedShapeIds.isEmpty ? [shapeId] : state.selectedShapeIds
                state.duplicateShapesToTemplates(Set(ids), direction: direction)
            } : nil,
            onToggleLock: { [shapeId = shape.id] in
                if !state.selectedShapeIds.contains(shapeId) {
                    state.selectShape(shapeId, in: row.id)
                }
                state.toggleLockOnSelection()
            },
            lockToggleWillUnlock: isInSelection ? facts.selectionFullyLocked : shape.resolvedIsLocked
        )
    }
}

extension EditorRowView {
    /// One pass over this row's shapes for every selection answer the menu and the canvas need.
    ///
    /// Deliberately derived from the caller's locale-resolved array rather than the equivalent
    /// `AppState` properties: those read `rows`, which would register `\AppState.rows` in every
    /// row's tracking scope and defeat this view's `.equatable()` (SCREENSHOT-BRO-W).
    func selectionFacts(in resolvedShapes: [CanvasShapeModel]) -> CanvasSelectionFacts {
        let isNonBaseLocale = !state.localeState.isBaseLocale
        let selected = resolvedShapes.filter { selectedShapeIds.contains($0.id) }
        let isMultiSelection = selectedShapeIds.count > 1
        return CanvasSelectionFacts(
            isNonBaseLocale: isNonBaseLocale,
            currentLocaleName: isNonBaseLocale ? state.localeState.activeLocaleLabel : nil,
            nonBaseLocaleCount: state.localeState.nonBaseLocaleCount,
            isMultiSelection: isMultiSelection,
            selectionFullyLocked: CanvasShapeModel.areFullyLocked(selected, ids: selectedShapeIds),
            // `!selected.isEmpty` matters: `allSatisfy` is vacuously true when the selection lives
            // in another row, where every one of these must read false.
            allSelectedSameType: isMultiSelection && !selected.isEmpty
                && selected.allSatisfy { $0.type == selected.first?.type },
            selectedTextShapeIds: isMultiSelection
                ? Set(selected.lazy.filter { $0.type == .text }.map(\.id))
                : [],
            allSelectedAreDevices: isMultiSelection
                && selected.count == selectedShapeIds.count
                && selected.allSatisfy { $0.type == .device }
        )
    }
}
