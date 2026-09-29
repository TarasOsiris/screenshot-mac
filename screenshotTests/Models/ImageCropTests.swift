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
}
