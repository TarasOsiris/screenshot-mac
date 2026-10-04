import SwiftUI

extension EditorRowView {
    /// Wires one canvas shape's gestures and text editing to the document.
    func shapeInteractions(
        for shape: CanvasShapeModel,
        isInSelection: Bool,
        isMulti: Bool,
        resolvedShapes: [CanvasShapeModel]
    ) -> CanvasShapeInteractions {
        CanvasShapeInteractions(
            // View mode: shapes are inert. The FAB sits in an overlay above the
            // canvas, but the shape tap is a `.simultaneousGesture` that co-recognizes
            // with the button tap, so a tap on the FAB can still reach a shape here.
            // Guard so any leaked tap can't select; `setViewMode` deselects regardless
            // of gesture order, leaving the canvas untouched.
            onSelect: { guard !state.viewMode.isViewMode else { return }; state.selectShape(shape.id, in: row.id) },
            onShiftSelect: { guard !state.viewMode.isViewMode else { return }; state.toggleShapeSelection(shape.id, in: row.id) },
            onUpdate: { state.updateShape($0) },
            onScreenshotDrop: { image, origin in
                state.saveImage(image, for: shape.id, source: origin)
            },
            onRequestImagePicker: { requestImagePicker(for: shape.id) },
            onBeginCrop: { guard !state.viewMode.isViewMode else { return }; state.beginImageCrop(shape.id) },
            onDragSnap: { draggedShape, rawOffset in
                let targets = dragSession.snapTargets {
                    AlignmentService.makeSnapTargets(
                        from: isInSelection
                            ? resolvedShapes.filter { !selectedShapeIds.contains($0.id) }
                            : resolvedShapes.filter { $0.id != draggedShape.id }
                    )
                }
                let threshold = 4 / row.displayScale(zoom: zoom)
                let result = AlignmentService.computeSnap(
                    draggedShape: draggedShape,
                    dragOffset: rawOffset,
                    otherShapeBounds: targets,
                    templateWidth: row.templateWidth,
                    templateHeight: row.templateHeight,
                    templateCount: row.templates.count,
                    snapThreshold: threshold
                )
                dragSession.publishGuides(result.guides)
                return result
            },
            // After the commit `handleDragEnded` already made, so the readout
            // hands the fields back to the document without a stale frame.
            onDragEnd: { endCanvasGesture(for: shape.id) },
            onOptionDragDuplicate: { shapeId in
                if isMulti {
                    state.duplicateShapesForOptionDrag()
                    return nil
                }
                return state.duplicateShapeForOptionDrag(shapeId)
            },
            onDragProgress: { offset in
                // Same-value writes still notify @Observable observers, so only
                // touch draggingShapeId on the first tick of a drag.
                if dragSession.draggingShapeId != shape.id {
                    dragSession.draggingShapeId = shape.id
                }
                dragSession.activeDragOffset = offset
                // The snapped offset, so the readout agrees with the guides.
                state.liveShapeGeometry.update(.init(shape, offsetBy: offset), for: shape.id)
            },
            onGroupDragEnd: { offset in
                state.applyGroupDrag(offset: offset)
                dragSession.endDrag()
            },
            onDidAppearAfterAdd: shape.id == state.canvasHints.justAddedShapeId ? { state.canvasHints.justAddedShapeId = nil } : nil,
            onEditingTextChanged: { editing in
                if state.textEdit.isActive != editing { state.textEdit.isActive = editing }
                if editing {
                    if textEditingShapeId != shape.id { textEditingShapeId = shape.id }
                } else if textEditingShapeId == shape.id {
                    textEditingShapeId = nil
                }
            },
            onCommitInlineText: { text, richText in
                state.commitInlineText(
                    shapeId: shape.id,
                    text: text,
                    richText: richText,
                    forLocaleCode: state.localeState.activeLocaleCode
                )
            },
            onInlineTextEditChanged: { shapeId, liveText, endEditing in
                if let liveText {
                    // Capture the editing locale now so a flush after the active
                    // locale changes still commits to the locale being edited.
                    let localeCode = state.localeState.activeLocaleCode
                    state.textEdit.registerInlineTextCommit(for: shapeId, endEditing: endEditing) {
                        let value = liveText()
                        state.commitInlineText(
                            shapeId: shapeId,
                            text: value.text,
                            richText: value.richText,
                            forLocaleCode: localeCode
                        )
                    }
                } else {
                    state.textEdit.clearInlineTextCommit(for: shapeId)
                }
            },
            onFormatBarStateChanged: { selState, controller in
                state.textEdit.richTextSelectionState = selState
                state.textEdit.richTextFormatController = controller
            },
            onFormatBarAnchorChanged: { anchor in
                state.textEdit.richTextFormatBarAnchor = anchor
            }
        )
    }
}
