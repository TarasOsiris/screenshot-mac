import Foundation

/// Which image shape is in crop mode, where a drag pans the picture instead of moving the shape.
/// Shared by the canvas, which pans, and the properties bar and inspector, which zoom.
@Observable
final class ImageCropSession {
    private(set) var shapeId: UUID?

    var isActive: Bool { shapeId != nil }

    func begin(_ shapeId: UUID) {
        guard self.shapeId != shapeId else { return }
        self.shapeId = shapeId
    }

    func end() {
        guard shapeId != nil else { return }
        shapeId = nil
    }
}
