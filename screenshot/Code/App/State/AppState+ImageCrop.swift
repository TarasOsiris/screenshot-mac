import SwiftUI

extension AppState {
    /// Cheap enough for a container body: no locale resolve, no image-dictionary read.
    func canCropImage(_ shape: CanvasShapeModel) -> Bool {
        shape.type == .image && shape.displayImageFileName != nil
    }

    /// Pixel size of the picture a resolved image shape shows; nil until it's decoded.
    func displayImageSize(of shape: CanvasShapeModel) -> CGSize? {
        guard shape.type == .image, let fileName = shape.displayImageFileName,
              let size = screenshotImages[fileName]?.size, size.width > 0, size.height > 0 else { return nil }
        return size
    }

    func beginImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        let shape = LocaleService.resolveShape(rows[location.rowIndex].shapes[location.shapeIndex], localeState: localeState)
        guard !shape.resolvedIsLocked, displayImageSize(of: shape) != nil else { return }
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

    /// Only a stored crop counts: an uncropped picture that overflows its frame is plain aspect fill,
    /// and resetting it would reshape a layout nobody cropped. Takes the resolved shape.
    func canResetImageCrop(_ shape: CanvasShapeModel) -> Bool {
        shape.type == .image && shape.imageCrop != nil && !shape.resolvedIsLocked
    }

    /// Grows the frame back around the whole picture, which stays where it is on the canvas. With the
    /// picture not decoded yet there's no size to grow to, so only the crop is cleared.
    func resetImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        // Resolved, so a non-base locale resets its own frame and crop, not the base's.
        var shape = LocaleService.resolveShape(rows[location.rowIndex].shapes[location.shapeIndex], localeState: localeState)
        guard canResetImageCrop(shape) else { return }
        if let size = displayImageSize(of: shape) {
            let uncropped = (shape.imageCrop ?? ImageCrop()).uncroppedFrame(of: shape.frameRect, rotation: shape.rotation, imageSize: size)
            shape.x = uncropped.minX
            shape.y = uncropped.minY
            shape.width = uncropped.width
            shape.height = uncropped.height
        }
        shape.imageCrop = nil
        updateShape(shape)
    }
}
