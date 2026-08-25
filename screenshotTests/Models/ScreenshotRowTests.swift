import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

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

    // MARK: - Marquee hit-testing

    private func marqueeRow() -> ScreenshotRow {
        ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 1000,
            templateHeight: 2000
        )
    }

    @Test func marqueeSelectsFullyCoveredShape() {
        let row = marqueeRow()
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        let hits = row.shapeIds(intersecting: CGRect(x: 0, y: 0, width: 400, height: 400), among: [shape])
        #expect(hits == [shape.id])
    }

    @Test func marqueeMissesDisjointShape() {
        let row = marqueeRow()
        let shape = CanvasShapeModel(type: .rectangle, x: 800, y: 800, width: 50, height: 50)
        let hits = row.shapeIds(intersecting: CGRect(x: 0, y: 0, width: 400, height: 400), among: [shape])
        #expect(hits.isEmpty)
    }

    @Test func marqueeSelectsPartiallyOverlappedShape() {
        let row = marqueeRow()
        // Only the shape's top-left corner falls inside the band — Sketch semantics select it.
        let shape = CanvasShapeModel(type: .rectangle, x: 380, y: 380, width: 200, height: 200)
        let hits = row.shapeIds(intersecting: CGRect(x: 0, y: 0, width: 400, height: 400), among: [shape])
        #expect(hits == [shape.id], "Intersection, not containment")
    }

    @Test func marqueeSelectsViaRotatedBounds() {
        let row = marqueeRow()
        // Unrotated this sits at x 300...340; rotated 45° its AABB widens well past 400.
        let shape = CanvasShapeModel(type: .rectangle, x: 300, y: 100, width: 40, height: 400, rotation: 45)
        let band = CGRect(x: 420, y: 280, width: 20, height: 20)
        #expect(row.shapeIds(intersecting: band, among: [shape]) == [shape.id])

        var unrotated = shape
        unrotated.rotation = 0
        #expect(row.shapeIds(intersecting: band, among: [unrotated]).isEmpty, "Same band misses it unrotated")
    }

    @Test func marqueeSkipsLockedShapes() {
        let row = marqueeRow()
        let free = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        var locked = CanvasShapeModel(type: .rectangle, x: 200, y: 100, width: 50, height: 50)
        locked.isLocked = true
        let hits = row.shapeIds(intersecting: CGRect(x: 0, y: 0, width: 400, height: 400), among: [free, locked])
        #expect(hits == [free.id])
    }

    @Test func marqueeIgnoresClippedShapeOutsideItsColumn() {
        let row = marqueeRow()
        // Centered in the second column, but wide enough that its AABB reaches back into the
        // first — where it isn't drawn, because it clips to its own template.
        var clipped = CanvasShapeModel(type: .rectangle, x: 600, y: 100, width: 900, height: 100)
        clipped.clipToTemplate = true
        let bandOverFirstColumn = CGRect(x: 620, y: 120, width: 40, height: 40)
        #expect(row.shapeIds(intersecting: bandOverFirstColumn, among: [clipped]).isEmpty)

        let bandOverOwnColumn = CGRect(x: 1100, y: 120, width: 40, height: 40)
        #expect(row.shapeIds(intersecting: bandOverOwnColumn, among: [clipped]) == [clipped.id])
    }

    @Test func marqueeSelectsWithZeroHeightBand() {
        let row = marqueeRow()
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        // A perfectly horizontal sweep. CGRect.intersects would report false here.
        let hits = row.shapeIds(intersecting: CGRect(x: 0, y: 120, width: 400, height: 0), among: [shape])
        #expect(hits == [shape.id])
    }

    @Test func containsShapeDetectsPressOnAShape() {
        let row = marqueeRow()
        let shape = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        #expect(row.containsShape(at: CGPoint(x: 120, y: 120), among: [shape]))
        #expect(!row.containsShape(at: CGPoint(x: 400, y: 400), among: [shape]))
    }

    @Test func containsShapeIncludesLockedShapes() {
        let row = marqueeRow()
        var locked = CanvasShapeModel(type: .rectangle, x: 100, y: 100, width: 50, height: 50)
        locked.isLocked = true
        // Unlike the sweep, this must see locked shapes — a locked shape still swallows the press.
        #expect(row.containsShape(at: CGPoint(x: 120, y: 120), among: [locked]))
        #expect(row.shapeIds(intersecting: CGRect(x: 110, y: 110, width: 20, height: 20), among: [locked]).isEmpty)
    }

    @Test func containsShapeRespectsTemplateClipping() {
        let row = marqueeRow()
        var clipped = CanvasShapeModel(type: .rectangle, x: 600, y: 100, width: 900, height: 100)
        clipped.clipToTemplate = true
        // Owns column 1, so the part of its box reaching back into column 0 isn't on screen.
        #expect(!row.containsShape(at: CGPoint(x: 650, y: 150), among: [clipped]))
        #expect(row.containsShape(at: CGPoint(x: 1100, y: 150), among: [clipped]))
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

    @Test func visibleShapesIncludesDeviceShadowOverlappingTemplate() {
        var device = CanvasShapeModel(
            type: .device,
            x: 220,
            y: 210,
            width: 160,
            height: 360,
            color: .clear,
            deviceCategory: .iphone
        )
        device.shadow = ShadowConfig(
            enabled: true,
            color: .black,
            radius: 45,
            offsetX: 65,
            offsetY: 0,
            opacity: 0.55
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 400,
            templateHeight: 800,
            shapes: [device]
        )

        let t1Shapes = row.visibleShapes(forTemplateAt: 1)
        #expect(t1Shapes.count == 1, "Device shadow overlaps into template 1")
        #expect(t1Shapes.first?.id == device.id)
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
        #expect(t0Shapes.isEmpty, "Clipped shape only visible in owning template")
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

    // MARK: - Blur gate

    /// This predicate is what routes a row's editor preview through the export renderer. When it
    /// only looked at `backgroundBlur`, a blurred per-template override drew with SwiftUI `.blur`
    /// in the editor and CIGaussianBlur in export — two different kernels, no parity.
    @Test func hasBlurredBackgroundCoversTemplateOverrides() {
        var row = ScreenshotRow(templates: [ScreenshotTemplate(), ScreenshotTemplate()])
        #expect(row.hasBlurredBackground == false, "Nothing blurred")

        row.backgroundBlur = 12
        #expect(row.hasBlurredBackground == true, "Row blur")

        row.backgroundBlur = 0
        row.templates[1].backgroundBlur = 12
        #expect(row.hasBlurredBackground == false, "Blur on a template that isn't overriding is inert")

        row.templates[1].overrideBackground = true
        #expect(row.hasBlurredBackground == true, "Enabled override with blur")

        row.templates[1].backgroundBlur = 0
        #expect(row.hasBlurredBackground == false, "Override without blur")
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
            isLabelManuallySet: true,
            excludeFromAppStoreConnect: true
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
        #expect(decoded.excludeFromAppStoreConnect == true)
    }

    @Test func inactiveBackgroundConfigsSurviveRoundTrip() throws {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()])
        row.gradientConfig = GradientConfig(angle: 42, gradientType: .radial)
        row.backgroundImageConfig = BackgroundImageConfig(fileName: "bg-1.png", fillMode: .tile)
        row.backgroundStyle = .color

        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(ScreenshotRow.self, from: data)

        #expect(decoded.backgroundStyle == .color)
        // Colors quantize to 8-bit on round-trip, so compare the lossless fields.
        #expect(decoded.gradientConfig.angle == 42, "Gradient tuned while another style is active must survive save")
        #expect(decoded.gradientConfig.gradientType == .radial)
        #expect(decoded.backgroundImageConfig.fileName == "bg-1.png", "Image reference must survive save or the file gets orphan-cleaned")
        #expect(decoded.backgroundImageConfig.fillMode == .tile)
    }

    @Test func templateConfigsSurviveRoundTripWithOverrideOff() throws {
        var template = ScreenshotTemplate()
        template.overrideBackground = false
        template.backgroundStyle = .gradient
        template.gradientConfig = GradientConfig(angle: 271)
        template.backgroundImageConfig = BackgroundImageConfig(fileName: "bg-2.png")
        template.backgroundBlur = 12

        let data = try JSONEncoder().encode(template)
        let decoded = try JSONDecoder().decode(ScreenshotTemplate.self, from: data)

        #expect(decoded.overrideBackground == false)
        #expect(decoded.backgroundStyle == .gradient)
        #expect(decoded.gradientConfig.angle == 271)
        #expect(decoded.backgroundImageConfig.fileName == "bg-2.png")
        #expect(decoded.backgroundBlur == 12)
    }

    @Test func excludeFromAppStoreConnectDefaultsFalse() {
        let row = ScreenshotRow()
        #expect(row.excludeFromAppStoreConnect == false)
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
        #expect(decoded.excludeFromAppStoreConnect == false, "Legacy rows default to included")
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
