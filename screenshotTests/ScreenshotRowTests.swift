import Testing
import Foundation
import SwiftUI
@testable import Screenshot_Bro

struct ScreenshotRowTests {

    // MARK: - Display scale

    @Test func displayScaleCapsAt500pxHeight() {
        let row = ScreenshotRow(templateHeight: 2688)
        let scale = row.displayScale()
        #expect(abs(scale - 500.0 / 2688.0) < 0.0001)
    }

    @Test func displayScaleNeverExceedsOne() {
        let row = ScreenshotRow(templateHeight: 400)
        #expect(row.displayScale() == 1.0, "Small templates don't upscale")
    }

    @Test func displayScaleIncludesZoom() {
        let row = ScreenshotRow(templateHeight: 2688)
        let baseScale = row.displayScale(zoom: 1.0)
        let zoomedScale = row.displayScale(zoom: 2.0)
        #expect(abs(zoomedScale - baseScale * 2.0) < 0.0001)
    }

    @Test func displayWidthAndHeight() {
        let row = ScreenshotRow(templateWidth: 1242, templateHeight: 2688)
        let scale = row.displayScale()
        #expect(abs(row.displayWidth() - 1242 * scale) < 0.01)
        #expect(abs(row.displayHeight() - 2688 * scale) < 0.01)
    }

    @Test func totalDisplayWidthMultipliesTemplates() {
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1242, templateHeight: 2688
        )
        let expected = row.displayWidth() * 3
        #expect(abs(row.totalDisplayWidth() - expected) < 0.01)
    }

    // MARK: - Resolution label

    @Test func resolutionLabelFormatted() {
        let row = ScreenshotRow(templateWidth: 1242, templateHeight: 2688)
        #expect(row.resolutionLabel == "1242\u{00d7}2688")
    }

    // MARK: - Template center X

    @Test func templateCenterXCalculation() {
        let row = ScreenshotRow(templateWidth: 1000)
        #expect(row.templateCenterX(at: 0) == 500)
        #expect(row.templateCenterX(at: 1) == 1500)
        #expect(row.templateCenterX(at: 2) == 2500)
    }

    // MARK: - Owning template index

    @Test func owningTemplateIndexByShapeCenter() {
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000
        )
        // Shape centered in first template
        let s1 = CanvasShapeModel(type: .rectangle, x: 400, y: 0, width: 200, height: 100)
        #expect(row.owningTemplateIndex(for: s1) == 0)

        // Shape centered in second template (center = 1100 + 100 = 1200)
        let s2 = CanvasShapeModel(type: .rectangle, x: 1100, y: 0, width: 200, height: 100)
        #expect(row.owningTemplateIndex(for: s2) == 1)

        // Shape centered in third template
        let s3 = CanvasShapeModel(type: .rectangle, x: 2400, y: 0, width: 200, height: 100)
        #expect(row.owningTemplateIndex(for: s3) == 2)
    }

    @Test func owningTemplateIndexClampsToValidRange() {
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000
        )
        // Shape far to the right, past all templates
        let s = CanvasShapeModel(type: .rectangle, x: 5000, y: 0, width: 100, height: 100)
        #expect(row.owningTemplateIndex(for: s) == 1, "Clamped to last template")

        // Shape far to the left
        let s2 = CanvasShapeModel(type: .rectangle, x: -500, y: 0, width: 100, height: 100)
        #expect(row.owningTemplateIndex(for: s2) == 0, "Clamped to first template")
    }

    // MARK: - Active shapes

    @Test func activeShapesFiltersDevicesWhenHidden() {
        let device = CanvasShapeModel(type: .device, x: 0, y: 0, width: 200, height: 400, deviceCategory: .iphone)
        let rect = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let row = ScreenshotRow(showDevice: false, shapes: [device, rect])
        #expect(row.activeShapes.count == 1)
        #expect(row.activeShapes.first?.type == .rectangle)
    }

    @Test func activeShapesIncludesDevicesWhenShown() {
        let device = CanvasShapeModel(type: .device, x: 0, y: 0, width: 200, height: 400, deviceCategory: .iphone)
        let rect = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let row = ScreenshotRow(showDevice: true, shapes: [device, rect])
        #expect(row.activeShapes.count == 2)
    }

    // MARK: - Visible shapes per template

    @Test func visibleShapesFiltersByTemplateBounds() {
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000,
            templateHeight: 2000,
            shapes: [
                CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 200, height: 200),  // In template 0
                CanvasShapeModel(type: .rectangle, x: 1100, y: 100, width: 200, height: 200), // In template 1
            ]
        )
        let t0Shapes = row.visibleShapes(forTemplateAt: 0)
        let t1Shapes = row.visibleShapes(forTemplateAt: 1)
        #expect(t0Shapes.count == 1)
        #expect(t1Shapes.count == 1)
    }

    @Test func visibleShapesIncludesOverlappingShape() {
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000,
            templateHeight: 2000,
            shapes: [
                // Shape spanning both templates (x=900 to x=1100)
                CanvasShapeModel(type: .rectangle, x: 900, y: 100, width: 200, height: 200),
            ]
        )
        let t0Shapes = row.visibleShapes(forTemplateAt: 0)
        let t1Shapes = row.visibleShapes(forTemplateAt: 1)
        #expect(t0Shapes.count == 1, "Shape overlaps into template 0")
        #expect(t1Shapes.count == 1, "Shape overlaps into template 1")
    }

    @Test func visibleShapesRespectsClipToTemplate() {
        let shape = CanvasShapeModel(
            type: .rectangle, x: 900, y: 100, width: 200, height: 200, clipToTemplate: true
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000,
            templateHeight: 2000,
            shapes: [shape]
        )
        // Shape center = 1000, owned by template 1 (floor(1000/1000) = 1)
        let t0Shapes = row.visibleShapes(forTemplateAt: 0)
        let t1Shapes = row.visibleShapes(forTemplateAt: 1)
        #expect(t0Shapes.count == 0, "Clipped shape only visible in owning template")
        #expect(t1Shapes.count == 1)
    }

    // MARK: - Spanning background

    @Test func isSpanningBackgroundOnlyForNonColorStyles() {
        var row = ScreenshotRow(backgroundStyle: .color)
        row.spanBackgroundAcrossRow = true
        #expect(row.isSpanningBackground == false, "Color style never spans")

        row.backgroundStyle = .gradient
        #expect(row.isSpanningBackground == true)

        row.backgroundStyle = .image
        #expect(row.isSpanningBackground == true)

        row.spanBackgroundAcrossRow = false
        #expect(row.isSpanningBackground == false, "Disabled when flag is off")
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let original = ScreenshotRow(
            label: "Test Row",
            templates: [ScreenshotTemplate()],
            templateWidth: 1242,
            templateHeight: 2688,
            backgroundStyle: .gradient,
            spanBackgroundAcrossRow: true,
            showDevice: false,
            showBorders: false,
            shapes: [CanvasShapeModel.defaultRectangle(centerX: 621, centerY: 1344)],
            isLabelManuallySet: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ScreenshotRow.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.label == "Test Row")
        #expect(decoded.templateWidth == 1242)
        #expect(decoded.backgroundStyle == .gradient)
        #expect(decoded.spanBackgroundAcrossRow == true)
        #expect(decoded.showDevice == false)
        #expect(decoded.showBorders == false)
        #expect(decoded.shapes.count == 1)
        #expect(decoded.isLabelManuallySet == true)
    }

    @Test func legacyRowWithoutDefaultDeviceCategoryDecodes() throws {
        let rowId = UUID()
        let templateId = UUID()
        let data = Data("""
        {
          "id": "\(rowId.uuidString)",
          "l": "Legacy Row",
          "tp": [
            {
              "id": "\(templateId.uuidString)",
              "bgc": "#0000FF"
            }
          ],
          "tw": 1242,
          "th": 2688,
          "bgc": "#0000FF"
        }
        """.utf8)

        let decoded = try JSONDecoder().decode(ScreenshotRow.self, from: data)

        #expect(decoded.id == rowId)
        #expect(decoded.label == "Legacy Row")
        #expect(decoded.templates.count == 1)
        #expect(decoded.defaultDeviceCategory == nil)
        #expect(decoded.showBorders == true)
        #expect(decoded.shapes.isEmpty)
    }

    @Test func backgroundImageConfigDecodesLegacyTileValuesIntoAxes() throws {
        let data = Data(#"{"fm":"tile","ts":0.25,"to":0.10,"tsc":1.4}"#.utf8)
        let decoded = try JSONDecoder().decode(BackgroundImageConfig.self, from: data)

        #expect(decoded.fillMode == .tile)
        #expect(decoded.tileSpacingX == 0.25)
        #expect(decoded.tileSpacingY == 0.25)
        #expect(decoded.tileOffsetX == 0.10)
        #expect(decoded.tileOffsetY == 0.10)
        #expect(decoded.tileScaleX == 1.4)
        #expect(decoded.tileScaleY == 1.4)
    }

    @Test func backgroundImageConfigRoundTripsIndependentTileAxes() throws {
        let original = BackgroundImageConfig(
            fileName: "tile.png",
            fillMode: .tile,
            tileSpacingX: 0.1,
            tileSpacingY: 0.25,
            tileOffsetX: 0.2,
            tileOffsetY: 0.4,
            tileScaleX: 1.5,
            tileScaleY: 0.8
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackgroundImageConfig.self, from: data)

        #expect(decoded.fileName == "tile.png")
        #expect(decoded.fillMode == .tile)
        #expect(decoded.tileSpacingX == 0.1)
        #expect(decoded.tileSpacingY == 0.25)
        #expect(decoded.tileOffsetX == 0.2)
        #expect(decoded.tileOffsetY == 0.4)
        #expect(decoded.tileScaleX == 1.5)
        #expect(decoded.tileScaleY == 0.8)
    }

}
