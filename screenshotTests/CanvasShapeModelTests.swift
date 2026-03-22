import Testing
import Foundation
import SwiftUI
@testable import Screenshot_Bro

struct CanvasShapeModelTests {

    // MARK: - AABB (axis-aligned bounding box)

    @Test func aabbNoRotation() {
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        let bb = shape.aabb
        #expect(bb.minX == 100)
        #expect(bb.minY == 200)
        #expect(bb.maxX == 400)
        #expect(bb.maxY == 600)
    }

    @Test func aabb90DegreeRotation() {
        // 300x400 shape rotated 90° → effectively 400x300
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 300, height: 400, rotation: 90)
        let bb = shape.aabb
        let cx: CGFloat = 150, cy: CGFloat = 200
        // After 90° rotation: halfW=200, halfH=150
        #expect(abs(bb.minX - (cx - 200)) < 0.01)
        #expect(abs(bb.minY - (cy - 150)) < 0.01)
        #expect(abs(bb.maxX - (cx + 200)) < 0.01)
        #expect(abs(bb.maxY - (cy + 150)) < 0.01)
    }

    @Test func aabb45DegreeRotation() {
        // 100x100 square rotated 45° → AABB is ~141x141
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 100, height: 100, rotation: 45)
        let bb = shape.aabb
        let cx: CGFloat = 50, cy: CGFloat = 50
        let expectedHalf = 50 * sqrt(2.0)
        #expect(abs(bb.minX - (cx - expectedHalf)) < 0.01)
        #expect(abs(bb.maxX - (cx + expectedHalf)) < 0.01)
        #expect(abs(bb.maxY - bb.minY - expectedHalf * 2) < 0.01)
    }

    @Test func aabb180DegreeRotationSameAsNoRotation() {
        let shape = CanvasShapeModel(type: .rectangle, x: 50, y: 50, width: 200, height: 100, rotation: 180)
        let bb = shape.aabb
        // 180° rotation should produce same AABB (symmetry)
        #expect(abs(bb.minX - 50) < 0.01)
        #expect(abs(bb.minY - 50) < 0.01)
        #expect(abs(bb.maxX - 250) < 0.01)
        #expect(abs(bb.maxY - 150) < 0.01)
    }

    // MARK: - Duplication

    @Test func duplicatedCreatesNewId() {
        let original = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        let copy = original.duplicated()
        #expect(copy.id != original.id)
        #expect(copy.x == original.x)
        #expect(copy.y == original.y)
        #expect(copy.width == original.width)
    }

    @Test func duplicatedAppliesOffset() {
        let original = CanvasShapeModel(type: .rectangle, x: 100, y: 200, width: 300, height: 400)
        let copy = original.duplicated(offsetX: 50, offsetY: 30)
        #expect(copy.x == 150)
        #expect(copy.y == 230)
    }

    // MARK: - displayImageFileName

    @Test func displayImageFileNameReturnsScreenshotForDevice() {
        var shape = CanvasShapeModel(type: .device, deviceCategory: .iphone)
        shape.screenshotFileName = "device-shot.png"
        shape.imageFileName = "other.png"
        #expect(shape.displayImageFileName == "device-shot.png")
    }

    @Test func displayImageFileNameReturnsImageFileForImageType() {
        var shape = CanvasShapeModel(type: .image)
        shape.imageFileName = "photo.png"
        shape.screenshotFileName = "other.png"
        #expect(shape.displayImageFileName == "photo.png")
    }

    @Test func setDisplayImageFileNameUpdatesCorrectProperty() {
        var deviceShape = CanvasShapeModel(type: .device, deviceCategory: .iphone)
        deviceShape.displayImageFileName = "new-screenshot.png"
        #expect(deviceShape.screenshotFileName == "new-screenshot.png")
        #expect(deviceShape.imageFileName == nil)

        var imageShape = CanvasShapeModel(type: .image)
        imageShape.displayImageFileName = "new-photo.png"
        #expect(imageShape.imageFileName == "new-photo.png")
    }

    // MARK: - allImageFileNames

    @Test func allImageFileNamesCollectsAll() {
        var shape = CanvasShapeModel(type: .device, deviceCategory: .iphone)
        shape.screenshotFileName = "screenshot.png"
        shape.imageFileName = "image.png"
        let names = shape.allImageFileNames
        #expect(names.contains("screenshot.png"))
        #expect(names.contains("image.png"))
        #expect(names.count == 2)
    }

    @Test func allImageFileNamesSkipsNil() {
        let shape = CanvasShapeModel(type: .rectangle)
        #expect(shape.allImageFileNames.isEmpty)
    }

    @Test func allImageFileNamesIncludesFillImage() {
        var shape = CanvasShapeModel(type: .rectangle)
        shape.fillImageConfig = BackgroundImageConfig(fileName: "fill-abc.png")
        let names = shape.allImageFileNames
        #expect(names.contains("fill-abc.png"))
        #expect(names.count == 1)
    }

    @Test func allImageFileNamesCollectsAllIncludingFill() {
        var shape = CanvasShapeModel(type: .device, deviceCategory: .iphone)
        shape.screenshotFileName = "screenshot.png"
        shape.imageFileName = "image.png"
        shape.fillImageConfig = BackgroundImageConfig(fileName: "fill.png")
        let names = shape.allImageFileNames
        #expect(names.contains("screenshot.png"))
        #expect(names.contains("image.png"))
        #expect(names.contains("fill.png"))
        #expect(names.count == 3)
    }

    // MARK: - Fill style properties

    @Test func resolvedFillStyleDefaultsToColor() {
        let shape = CanvasShapeModel(type: .rectangle)
        #expect(shape.resolvedFillStyle == .color)
        #expect(shape.fillStyle == nil)
    }

    @Test func resolvedFillStyleReturnsExplicitValue() {
        var shape = CanvasShapeModel(type: .rectangle)
        shape.fillStyle = .gradient
        #expect(shape.resolvedFillStyle == .gradient)
    }

    @Test func fillPropertiesRoundTripThroughCodable() throws {
        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        shape.fillStyle = .gradient
        shape.fillGradientConfig = GradientConfig(
            color1: .red, color2: .blue, angle: 90
        )
        shape.fillImageConfig = BackgroundImageConfig(fileName: "test.png", fillMode: .tile)

        let data = try JSONEncoder().encode(shape)
        let decoded = try JSONDecoder().decode(CanvasShapeModel.self, from: data)

        #expect(decoded.fillStyle == .gradient)
        #expect(decoded.fillGradientConfig?.angle == 90)
        #expect(decoded.fillGradientConfig?.stops.count == 2)
        #expect(decoded.fillImageConfig?.fileName == "test.png")
        #expect(decoded.fillImageConfig?.fillMode == .tile)
    }

    @Test func fillPropertiesNilByDefaultAfterDecode() throws {
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        let data = try JSONEncoder().encode(shape)
        let decoded = try JSONDecoder().decode(CanvasShapeModel.self, from: data)

        #expect(decoded.fillStyle == nil)
        #expect(decoded.fillGradientConfig == nil)
        #expect(decoded.fillImageConfig == nil)
    }

    @Test func lineHeightMultipleRoundTripsThroughCodable() throws {
        let shape = CanvasShapeModel(
            type: .text,
            x: 0,
            y: 0,
            width: 100,
            height: 100,
            text: "Hello",
            fontSize: 32,
            lineHeightMultiple: 0.85
        )

        let data = try JSONEncoder().encode(shape)
        let decoded = try JSONDecoder().decode(CanvasShapeModel.self, from: data)

        #expect(decoded.lineHeightMultiple == 0.85)
        #expect(decoded.lineSpacing == nil)
    }

    @Test func lineHeightMultipleDefaultsToNilAfterDecode() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","t":"text","x":0,"y":0,"w":100,"h":100,"c":"#FFFFFF","txt":"Hello"}
        """
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CanvasShapeModel.self, from: data)

        #expect(decoded.lineHeightMultiple == nil)
    }

    @Test func duplicatedPreservesFillProperties() {
        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 100, height: 100)
        shape.fillStyle = .gradient
        shape.fillGradientConfig = GradientConfig()
        shape.fillImageConfig = BackgroundImageConfig(fileName: "fill.png")

        let copy = shape.duplicated(offsetX: 10, offsetY: 20)
        #expect(copy.fillStyle == .gradient)
        #expect(copy.fillGradientConfig != nil)
        #expect(copy.fillImageConfig?.fileName == "fill.png")
        #expect(copy.id != shape.id)
    }

    @Test func supportsFillMatchesSupportsOutline() {
        for type in ShapeType.allCases {
            #expect(type.supportsFill == type.supportsOutline)
        }
    }

    // MARK: - Factory methods produce correct defaults

    @Test func defaultRectangleCentered() {
        let cx: CGFloat = 500, cy: CGFloat = 1000
        let shape = CanvasShapeModel.defaultRectangle(centerX: cx, centerY: cy)
        #expect(shape.type == .rectangle)
        #expect(shape.x == cx - shape.width / 2)
        #expect(shape.y == cy - shape.height / 2)
        #expect(shape.width > 0)
        #expect(shape.height > 0)
    }

    @Test func defaultCircleCentered() {
        let cx: CGFloat = 500, cy: CGFloat = 1000
        let shape = CanvasShapeModel.defaultCircle(centerX: cx, centerY: cy)
        #expect(shape.type == .circle)
        #expect(shape.x == cx - shape.width / 2)
        #expect(shape.y == cy - shape.height / 2)
        #expect(shape.width == shape.height)
    }

    @Test func defaultTextHasContent() {
        let shape = CanvasShapeModel.defaultText(centerX: 500, centerY: 1000)
        #expect(shape.type == .text)
        #expect(shape.text != nil && !shape.text!.isEmpty)
        #expect(shape.fontSize != nil && shape.fontSize! > 0)
        #expect(shape.fontWeight == 700)
    }

    @Test func defaultStarHasPointCount() {
        let shape = CanvasShapeModel.defaultStar(centerX: 500, centerY: 500)
        #expect(shape.type == .star)
        #expect(shape.starPointCount == 5)
    }

    @Test func defaultDeviceScalesTo80PercentHeight() {
        let templateHeight: CGFloat = 2688
        let shape = CanvasShapeModel.defaultDevice(centerX: 621, centerY: 1344, templateHeight: templateHeight)
        #expect(shape.type == .device)
        #expect(abs(shape.height - templateHeight * 0.8) < 0.01)
    }

    // MARK: - Device aspect ratio adjustment

    @Test func adjustToDeviceAspectRatioPreservesHeight() {
        var shape = CanvasShapeModel(type: .device, x: 0, y: 0, width: 500, height: 1000, deviceCategory: .iphone)
        let originalHeight = shape.height
        shape.adjustToDeviceAspectRatio()
        #expect(shape.height == originalHeight)
        let base = DeviceCategory.iphone.baseDimensions
        let expectedAspect = base.width / base.height
        let actualAspect = shape.width / shape.height
        #expect(abs(actualAspect - expectedAspect) < 0.01)
    }

    @Test func adjustToDeviceAspectRatioCentersAtX() {
        var shape = CanvasShapeModel(type: .device, x: 0, y: 0, width: 500, height: 1000, deviceCategory: .iphone)
        shape.adjustToDeviceAspectRatio(centerX: 600)
        #expect(abs((shape.x + shape.width / 2) - 600) < 0.01)
    }

    // MARK: - ShapeType properties

    @Test func shapeMenuTypesAreBasicShapes() {
        #expect(ShapeType.shapeMenuTypes == [.rectangle, .circle, .star])
    }

    @Test func outlineSupportedOnlyForBasicShapes() {
        #expect(ShapeType.rectangle.supportsOutline == true)
        #expect(ShapeType.circle.supportsOutline == true)
        #expect(ShapeType.star.supportsOutline == true)
        #expect(ShapeType.text.supportsOutline == false)
        #expect(ShapeType.image.supportsOutline == false)
        #expect(ShapeType.device.supportsOutline == false)
        #expect(ShapeType.svg.supportsOutline == false)
    }
}
