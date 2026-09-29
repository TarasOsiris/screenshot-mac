import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

struct ImageCropTests {
    @Test func offsetsClampSoTheImageStillCoversTheFrame() {
        // A square image in a square frame at 2×: the picture overhangs by half a frame each way.
        let crop = ImageCrop(scale: 2, offsetX: 3, offsetY: -3)
            .clamped(imageAspect: 1, frameSize: CGSize(width: 100, height: 100))
        #expect(crop.offsetX == 0.5)
        #expect(crop.offsetY == -0.5)
    }

    @Test func unzoomedWideImageOnlyPansAlongItsOverhang() {
        // 2:1 image in a square frame fills to 200×100, so it can slide sideways but not vertically.
        let crop = ImageCrop(scale: 1, offsetX: 1, offsetY: 1)
            .clamped(imageAspect: 2, frameSize: CGSize(width: 100, height: 100))
        #expect(crop.offsetX == 0.5)
        #expect(crop.offsetY == 0)
    }

    @Test func scaleClampsToItsRange() {
        #expect(ImageCrop(scale: 0.2).clamped(imageAspect: 1, frameSize: CGSize(width: 10, height: 10)).scale == 1)
        #expect(ImageCrop(scale: 50).clamped(imageAspect: 1, frameSize: CGSize(width: 10, height: 10)).scale == ImageCrop.scaleRange.upperBound)
    }

    @Test func cropRoundTripsAndOldShapesDecodeWithout() throws {
        var shape = CanvasShapeModel(type: .image)
        shape.imageCrop = ImageCrop(scale: 2, offsetX: 0.25, offsetY: -0.1)
        let data = try JSONEncoder().encode(shape)
        #expect(try JSONDecoder().decode(CanvasShapeModel.self, from: data).imageCrop == shape.imageCrop)

        let legacy = try JSONEncoder().encode(CanvasShapeModel(type: .image))
        #expect(String(data: legacy, encoding: .utf8)?.contains("icr") == false)
        #expect(try JSONDecoder().decode(CanvasShapeModel.self, from: legacy).imageCrop == nil)
    }

    @Test func settingScaleBackToOneClearsTheCrop() {
        var shape = CanvasShapeModel(type: .image)
        shape.imageCropScale = 3
        #expect(shape.imageCrop?.scale == 3)
        shape.imageCropScale = 1
        #expect(shape.imageCrop == nil)
    }

    // MARK: - Crop-mode resize

    private func imageShape(frame: CGRect, rotation: Double = 0, crop: ImageCrop? = nil) -> CanvasShapeModel {
        var shape = CanvasShapeModel(type: .image)
        shape.x = frame.minX
        shape.y = frame.minY
        shape.width = frame.width
        shape.height = frame.height
        shape.rotation = rotation
        shape.imageCrop = crop
        return shape
    }

    /// The picture's four corners on the canvas, for comparing before and after a refit.
    private func pictureCorners(_ crop: ImageCrop, frame: CGRect, rotation: Double, imageSize: CGSize) -> [CGPoint] {
        let rect = crop.pictureRect(imageSize: imageSize, frameSize: frame.size)
        return [
            CGSize(width: rect.minX, height: rect.minY), CGSize(width: rect.maxX, height: rect.minY),
            CGSize(width: rect.minX, height: rect.maxY), CGSize(width: rect.maxX, height: rect.maxY),
        ].map { corner in
            let canvas = ShapeRotation.toCanvas(corner, degrees: rotation)
            return CGPoint(x: frame.midX + canvas.width, y: frame.midY + canvas.height)
        }
    }

    private func expectClose(_ a: [CGPoint], _ b: [CGPoint], sourceLocation: SourceLocation = #_sourceLocation) {
        for (p, q) in zip(a, b) {
            #expect(abs(p.x - q.x) < 1e-6 && abs(p.y - q.y) < 1e-6, "\(p) != \(q)", sourceLocation: sourceLocation)
        }
    }

    @Test(arguments: [0.0, 30.0])
    func handleDragsTrimTheWindowAndLeaveThePictureWhereItWas(rotation: Double) throws {
        let imageSize = CGSize(width: 400, height: 300)
        let frame = CGRect(x: 100, y: 200, width: 200, height: 200)
        let shape = imageShape(frame: frame, rotation: rotation, crop: ImageCrop(scale: 1.5, offsetX: 0.1, offsetY: -0.05))
        let before = pictureCorners(shape.imageCrop!, frame: frame, rotation: rotation, imageSize: imageSize)

        for edge in ResizeEdge.allCases {
            let raw = ResizeGeometry.resize(shape: shape, edge: edge, translation: CGSize(width: 37, height: -23), lockAspectRatio: false)
            let state = ResizeGeometry.cropResize(raw, base: shape, edge: edge, imageSize: imageSize)
            let crop = try #require(state.imageCrop)
            expectClose(pictureCorners(crop, frame: state.frame, rotation: rotation, imageSize: imageSize), before)
            #expect(crop.scale >= ImageCrop.scaleRange.lowerBound && crop.scale <= ImageCrop.scaleRange.upperBound)
        }
    }

    @Test func windowCannotGrowPastThePicture() {
        // A square picture exactly filling its frame: every outward drag is refused.
        let imageSize = CGSize(width: 100, height: 100)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let shape = imageShape(frame: frame)
        let raw = ResizeGeometry.resize(shape: shape, edge: .topLeft, translation: CGSize(width: -40, height: -40), lockAspectRatio: false)
        let state = ResizeGeometry.cropResize(raw, base: shape, edge: .topLeft, imageSize: imageSize)
        #expect(abs(state.newX) < 1e-9 && abs(state.newY) < 1e-9)
        #expect(abs(state.newW - 100) < 1e-9 && abs(state.newH - 100) < 1e-9)
    }

    @Test func windowStopsAtTheMaximumZoom() {
        let imageSize = CGSize(width: 100, height: 100)
        let shape = imageShape(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let raw = ResizeGeometry.resize(shape: shape, edge: .bottomRight, translation: CGSize(width: -95, height: -95), lockAspectRatio: false)
        let state = ResizeGeometry.cropResize(raw, base: shape, edge: .bottomRight, imageSize: imageSize)
        let crop = ImageCrop().refitted(from: CGRect(x: 0, y: 0, width: 100, height: 100), to: state.frame, rotation: 0, imageSize: imageSize)
        #expect(abs(crop.scale - ImageCrop.scaleRange.upperBound) < 1e-9)
    }

    @Test func cropWindowAlwaysStaysInsideThePicture() {
        let imageSize = CGSize(width: 300, height: 200)
        let frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let shape = imageShape(frame: frame, crop: ImageCrop(scale: 2, offsetX: -0.5, offsetY: 0.3))
        let picture = shape.imageCrop!.pictureRect(imageSize: imageSize, frameSize: frame.size)
        for edge in ResizeEdge.allCases {
            for dx in stride(from: -150.0, through: 150, by: 25) {
                for dy in stride(from: -150.0, through: 150, by: 25) {
                    let raw = ResizeGeometry.resize(shape: shape, edge: edge, translation: CGSize(width: dx, height: dy), lockAspectRatio: false)
                    let state = ResizeGeometry.cropResize(raw, base: shape, edge: edge, imageSize: imageSize)
                    let center = ImageCrop.localOffset(from: frame, to: state.frame, rotation: 0)
                    let window = CGRect(x: center.width - state.newW / 2, y: center.height - state.newH / 2, width: state.newW, height: state.newH)
                    #expect(picture.insetBy(dx: -1e-9, dy: -1e-9).contains(window), "\(edge) \(dx),\(dy)")
                }
            }
        }
    }

    @Test func refittingAnUntouchedFrameStoresNoCrop() {
        let frame = CGRect(x: 10, y: 20, width: 120, height: 90)
        let crop = ImageCrop().refitted(from: frame, to: frame, rotation: 17, imageSize: CGSize(width: 1200, height: 900))
        #expect(crop.storedValue == nil)
    }
}
