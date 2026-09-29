#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension AppState {
    func canCropImage(_ shape: CanvasShapeModel) -> Bool {
        shape.type == .image && imageAspect(for: shape) != nil
    }

    /// Width / height of the picture the shape shows in the active locale.
    func imageAspect(for shape: CanvasShapeModel) -> CGFloat? {
        let resolved = LocaleService.resolveShape(shape, localeState: localeState)
        guard let fileName = resolved.displayImageFileName,
              let size = screenshotImages[fileName]?.size,
              size.width > 0, size.height > 0 else { return nil }
        return size.width / size.height
    }

    func beginImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId),
              canCropImage(rows[location.rowIndex].shapes[location.shapeIndex]) else { return }
        selectShape(shapeId, in: rows[location.rowIndex].id)
        imageCrop.begin(shapeId)
    }

    func toggleImageCrop(_ shapeId: UUID) {
        if imageCrop.shapeId == shapeId {
            imageCrop.end()
        } else {
            beginImageCrop(shapeId)
        }
    }

    func resetImageCrop(_ shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }
        var shape = rows[location.rowIndex].shapes[location.shapeIndex]
        guard shape.imageCrop != nil else { return }
        shape.imageCrop = nil
        updateShape(shape)
    }
}
