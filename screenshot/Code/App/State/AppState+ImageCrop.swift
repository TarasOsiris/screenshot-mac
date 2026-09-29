import Foundation

extension AppState {
    /// Cheap enough for a container body: no locale resolve, no image-dictionary read.
    func canCropImage(_ shape: CanvasShapeModel) -> Bool {
        shape.type == .image && shape.displayImageFileName != nil
    }

    func beginImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        let shape = LocaleService.resolveShape(rows[location.rowIndex].shapes[location.shapeIndex], localeState: localeState)
        guard canCropImage(shape), !shape.resolvedIsLocked,
              let fileName = shape.displayImageFileName, screenshotImages[fileName] != nil else { return }
        selectShape(shapeId, in: rows[location.rowIndex].id)
        imageCrop.begin(shapeId)
    }

    func toggleImageCrop(_ shapeId: UUID) {
        if imageCrop.shapeId == shapeId {
            endImageCrop()
        } else {
            beginImageCrop(shapeId)
        }
    }

    /// Esc and Return leave crop mode first; false when there was none to leave.
    @discardableResult
    func endImageCrop() -> Bool {
        guard imageCrop.isActive else { return false }
        imageCrop.end()
        return true
    }

    func resetImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        // Resolved, so a non-base locale resets its own crop instead of writing the base frame over its override.
        var shape = LocaleService.resolveShape(rows[location.rowIndex].shapes[location.shapeIndex], localeState: localeState)
        guard shape.imageCrop != nil, !shape.resolvedIsLocked else { return }
        shape.imageCrop = nil
        updateShape(shape)
    }
}
