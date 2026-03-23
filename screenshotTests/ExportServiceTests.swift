import Testing
import AppKit
import SwiftUI
@testable import Screenshot_Bro

@MainActor
struct ExportServiceTests {

    // MARK: - Opaque PNG

    @Test func opaquePNGProducesValidData() throws {
        let image = makeTestImage(width: 200, height: 400)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        #expect(pngData.count > 0)

        let decoded = try #require(NSBitmapImageRep(data: pngData))
        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 400)
    }

    @Test func opaquePNGHasNoAlphaChannel() throws {
        let image = makeTestImage(width: 100, height: 100)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        let decoded = try #require(NSBitmapImageRep(data: pngData))
        #expect(decoded.hasAlpha == false)
        #expect(decoded.samplesPerPixel == 3)
    }

    @Test func opaquePNGCompositsTransparencyOnWhite() throws {
        // Create a fully transparent image
        let size = NSSize(width: 10, height: 10)
        let transparentImage = NSImage(size: size)
        transparentImage.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        transparentImage.unlockFocus()

        let pngData = try #require(ExportService.opaquePNGData(from: transparentImage))
        let decoded = try #require(NSBitmapImageRep(data: pngData))

        // Transparent pixels should become white (255,255,255)
        let color = try #require(decoded.colorAt(x: 5, y: 5))
        let r = color.redComponent
        let g = color.greenComponent
        let b = color.blueComponent
        #expect(r > 0.99)
        #expect(g > 0.99)
        #expect(b > 0.99)
    }

    // MARK: - Opaque JPEG

    @Test func opaqueJPEGProducesValidData() throws {
        let image = makeTestImage(width: 200, height: 400)
        let jpegData = try #require(ExportService.opaqueJPEGData(from: image))
        #expect(jpegData.count > 0)

        let decoded = try #require(NSBitmapImageRep(data: jpegData))
        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 400)
    }

    // MARK: - Large image (App Store dimensions)

    @Test func opaquePNGWorksAtAppStoreDimensions() throws {
        let image = makeTestImage(width: 1242, height: 2688)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        let decoded = try #require(NSBitmapImageRep(data: pngData))
        #expect(decoded.pixelsWide == 1242)
        #expect(decoded.pixelsHigh == 2688)
        #expect(decoded.hasAlpha == false)
    }

    // MARK: - Template rendering

    @Test func renderTemplatePNGProducesData() throws {
        let row = makeTestRow(width: 200, height: 400)
        let pngData = try #require(ExportService.renderTemplatePNG(index: 0, row: row))
        #expect(pngData.count > 0)

        let decoded = try #require(NSBitmapImageRep(data: pngData))
        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 400)
        #expect(decoded.hasAlpha == false)
    }

    @Test func renderTemplateDataPNG() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(ExportService.renderTemplateData(
            index: 0, row: row, format: .png
        ))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.hasAlpha == false)
    }

    @Test func renderTemplateDataJPEG() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(ExportService.renderTemplateData(
            index: 0, row: row, format: .jpeg
        ))
        #expect(data.count > 0)
    }

    // MARK: - Oversized shapes must not shift layout

    /// When a shape extends beyond the template boundary, the rendered image must still
    /// be aligned to the top-left — the background should fill all four corners.
    /// Regression test for: shapes using .offset() can make the ZStack larger than the
    /// template frame; without alignment: .topLeading the default .center alignment
    /// shifts everything, leaving gaps at the edges.
    @Test func oversizedShapeDoesNotShiftRenderedBackground() throws {
        let (row, tw, th) = makeOversizedShapeRow(
            shapeX: 0.5, shapeY: 0.5, shapeW: 3.0, shapeH: 2.0
        )

        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        #expect(bitmap.pixelsWide == Int(tw))
        #expect(bitmap.pixelsHigh == Int(th))

        // Bottom-center must be red, not white (the centering-shift symptom).
        try expectDominant(bitmap, at: (Int(tw) / 2, Int(th) - 3), channel: .r, label: "bottom-center")
    }

    /// Same regression test but for the second template in a multi-template row,
    /// where the oversized shape spans from template 0 into template 1.
    @Test func oversizedShapeDoesNotShiftSecondTemplateRendering() throws {
        let (row, tw, th) = makeOversizedShapeRow(
            shapeX: 0.8, shapeY: 0, shapeW: 2.0, shapeH: 0.5
        )

        let bitmap = try renderTemplateBitmap(index: 1, row: row)

        for (label, x, y) in [("bottom-left", 2, Int(th) - 3), ("bottom-right", Int(tw) - 3, Int(th) - 3)] {
            try expectDominant(bitmap, at: (x, y), channel: .r, label: label)
        }
    }

    // MARK: - Export / editor parity
    //
    // These tests verify that ExportService.renderTemplateImage produces pixel-accurate
    // output matching what the editor canvas shows. Each test creates a row with known
    // geometry, renders via the export path, and samples specific pixels.
    //
    // Color assertions use dominant-channel checks (e.g. "red > green + margin")
    // instead of absolute sRGB thresholds, because SwiftUI colors may render in
    // Display P3 and convert slightly during the PNG round-trip.

    @Test func solidColorBackgroundFillsEntireTemplate() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 400
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            bgColor: .red
        )
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // All four corners + center must be red-dominant
        for (label, x, y) in [
            ("top-left", 2, 2), ("top-right", Int(tw) - 3, 2),
            ("bottom-left", 2, Int(th) - 3), ("bottom-right", Int(tw) - 3, Int(th) - 3),
            ("center", Int(tw) / 2, Int(th) / 2),
        ] {
            try expectDominant(bitmap, at: (x, y), channel: .r, label: label)
        }
    }

    @Test func shapeAppearsAtCorrectPositionInTemplate() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 400
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 150, y: 150, width: 100, height: 100,
            color: Self.testRed
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        try expectDominant(bitmap, at: (200, 200), channel: .r, label: "shape center")
        try expectDominant(bitmap, at: (50, 50), channel: .b, label: "outside shape")
        try expectDominant(bitmap, at: (300, 300), channel: .b, label: "below shape")
    }

    @Test func shapeStraddlingTwoTemplatesAppearsInBoth() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 400
        var row = makeTestRow(width: tw, height: th, templateCount: 2, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 350, y: 150, width: 100, height: 100,
            color: Self.testRed
        )]

        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        try expectDominant(bmp0, at: (375, 200), channel: .r, label: "t0: shape visible")
        try expectDominant(bmp0, at: (100, 200), channel: .b, label: "t0: background")

        let bmp1 = try renderTemplateBitmap(index: 1, row: row)
        try expectDominant(bmp1, at: (25, 200), channel: .r, label: "t1: shape visible")
        try expectDominant(bmp1, at: (200, 200), channel: .b, label: "t1: background")
    }

    @Test func templateOverrideBackgroundReplacesRowBackground() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        var t1 = ScreenshotTemplate(backgroundColor: Color(red: 0, green: 0.8, blue: 0))
        t1.overrideBackground = true
        t1.backgroundStyle = .color

        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), t1],
            templateWidth: tw, templateHeight: th,
            bgColor: Self.testRed
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        try expectDominant(bmp0, at: (100, 100), channel: .r, label: "t0: row bg red")

        let bmp1 = try renderTemplateBitmap(index: 1, row: row)
        try expectDominant(bmp1, at: (100, 100), channel: .g, label: "t1: override bg green")
    }

    @Test func spanningGradientIsContinuousAcrossTemplates() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 90 // left to right
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        let bmp1 = try renderTemplateBitmap(index: 1, row: row)

        // Template 0 center should be red-dominant, template 1 blue-dominant
        let c0 = try pixelColor(bmp0, at: (100, 100))
        #expect(c0.r > c0.b, "t0 center should be red-dominant, got r=\(c0.r) b=\(c0.b)")
        let c1 = try pixelColor(bmp1, at: (100, 100))
        #expect(c1.b > c1.r, "t1 center should be blue-dominant, got r=\(c1.r) b=\(c1.b)")

        // Continuity: right edge of t0 should approximate left edge of t1
        let t0Right = try pixelColor(bmp0, at: (Int(tw) - 2, 100))
        let t1Left = try pixelColor(bmp1, at: (1, 100))
        let delta = abs(t0Right.r - t1Left.r) + abs(t0Right.g - t1Left.g) + abs(t0Right.b - t1Left.b)
        #expect(delta < 0.15, "Spanning gradient should be continuous at boundary, delta=\(delta)")
    }

    @Test func spanningRadialGradientIsContinuousAcrossTemplates() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 0,
            gradientType: .radial
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        let bmp1 = try renderTemplateBitmap(index: 1, row: row)

        // Continuity: right edge of t0 should approximate left edge of t1
        let t0Right = try pixelColor(bmp0, at: (Int(tw) - 2, 100))
        let t1Left = try pixelColor(bmp1, at: (1, 100))
        let delta = abs(t0Right.r - t1Left.r) + abs(t0Right.g - t1Left.g) + abs(t0Right.b - t1Left.b)
        #expect(delta < 0.15, "Spanning radial gradient should be continuous at boundary, delta=\(delta)")
    }

    @Test func spanningAngularGradientRendersAcrossTemplates() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 0,
            gradientType: .angular
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        let bmp1 = try renderTemplateBitmap(index: 1, row: row)

        // Templates should show different slices of the spanning gradient
        let c0 = try pixelColor(bmp0, at: (50, 50))
        let c1 = try pixelColor(bmp1, at: (50, 50))
        let sampleDelta = abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b)
        #expect(sampleDelta > 0.05, "Spanning angular templates should show different colors at same position")
    }

    @Test func nonSpanningGradientRendersPerTemplate() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        for gradType in [GradientType.linear, .radial, .angular] {
            let gradient = GradientConfig(
                stops: [
                    GradientColorStop(color: Self.testRed, location: 0),
                    GradientColorStop(color: Self.testBlue, location: 1),
                ],
                angle: 90,
                gradientType: gradType
            )
            let row = ScreenshotRow(
                templates: [ScreenshotTemplate(), ScreenshotTemplate()],
                templateWidth: tw, templateHeight: th,
                backgroundStyle: .gradient,
                gradientConfig: gradient,
                spanBackgroundAcrossRow: false
            )

            let bmp0 = try renderTemplateBitmap(index: 0, row: row)
            let bmp1 = try renderTemplateBitmap(index: 1, row: row)

            // Non-spanning: both templates should look identical at their centers
            let c0 = try pixelColor(bmp0, at: (100, 100))
            let c1 = try pixelColor(bmp1, at: (100, 100))
            let delta = abs(c0.r - c1.r) + abs(c0.g - c1.g) + abs(c0.b - c1.b)
            #expect(delta < 0.05, "\(gradType): non-spanning templates should be identical, delta=\(delta)")
        }
    }

    @Test func clipToTemplateRestrictsShapeToOwningTemplate() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 400
        var row = makeTestRow(width: tw, height: th, templateCount: 2, bgColor: Self.testBlue)
        // Shape center at x=400 → owningTemplate = floor(400/400) = 1
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 350, y: 150, width: 100, height: 100,
            color: Self.testRed, clipToTemplate: true
        )]

        // Template 0: shape should NOT appear
        let bmp0 = try renderTemplateBitmap(index: 0, row: row)
        try expectDominant(bmp0, at: (375, 200), channel: .b, label: "t0: clipped away")

        // Template 1: shape visible
        let bmp1 = try renderTemplateBitmap(index: 1, row: row)
        try expectDominant(bmp1, at: (25, 200), channel: .r, label: "t1: shape visible")
    }

    @Test func opacityBlendingCompositsCorrectly() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 0, y: 0, width: tw, height: th,
            color: Self.testRed, opacity: 0.5
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // Blend of red over blue → both channels present
        let c = try pixelColor(bitmap, at: (100, 100))
        #expect(c.r > 0.2, "Should have red from shape, got r=\(c.r)")
        #expect(c.b > 0.2, "Should have blue from background, got b=\(c.b)")
    }

    @Test func borderRadiusCutsCorners() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 0, y: 0, width: 200, height: 200,
            borderRadius: 60, color: Color(red: 0.9, green: 0, blue: 0)
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // Corner: outside radius → background (blue)
        try expectDominant(bitmap, at: (3, 3), channel: .b, label: "corner: outside radius")
        // Center: inside shape → red
        try expectDominant(bitmap, at: (100, 100), channel: .r, label: "center: inside shape")
    }

    @Test func rotatedShapeRendersAtCorrectLocation() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 400
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 100, y: 150, width: 200, height: 100,
            rotation: 45, color: Color(red: 0.9, green: 0, blue: 0)
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // Center of shape should be red
        try expectDominant(bitmap, at: (200, 200), channel: .r, label: "rotated shape center")
        // Far corner should be background
        try expectDominant(bitmap, at: (10, 10), channel: .b, label: "far corner: background")
    }

    @Test func deviceAspectRatioIsNormalizedInExport() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        // iPhone aspect ~0.489. Square shape → normalization narrows it.
        row.shapes = [CanvasShapeModel(
            type: .device, x: 50, y: 100, width: 300, height: 300,
            color: .clear, deviceCategory: .iphone
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // After normalization the device is narrower; original right edge (350) is background
        try expectDominant(bitmap, at: (340, 250), channel: .b, label: "right of normalized device")
    }

    @Test func outlineRendersAtShapeEdge() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 200
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 30, y: 30, width: 140, height: 140,
            color: .white, outlineColor: .black, outlineWidth: 10
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        // Center: white fill
        let center = try pixelColor(bitmap, at: (100, 100))
        #expect(center.r > 0.8 && center.g > 0.8 && center.b > 0.8, "Center should be white")
        // Edge: dark outline
        let edge = try pixelColor(bitmap, at: (33, 100))
        let brightness = (edge.r + edge.g + edge.b) / 3
        #expect(brightness < 0.4, "Edge should be dark (outline), got brightness=\(brightness)")
    }

    @Test func maxRadiusOutlineStaysInsideCapsuleBounds() throws {
        let tw: CGFloat = 220
        let th: CGFloat = 120
        var row = makeTestRow(width: tw, height: th, bgColor: Self.testBlue)
        row.shapes = [CanvasShapeModel(
            type: .rectangle, x: 20, y: 20, width: 180, height: 80,
            borderRadius: 999, color: .white, outlineColor: .black, outlineWidth: 8
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        let center = try pixelColor(bitmap, at: (110, 60))
        #expect(center.r > 0.8 && center.g > 0.8 && center.b > 0.8, "Center should stay white")

        let edge = try pixelColor(bitmap, at: (24, 60))
        let brightness = (edge.r + edge.g + edge.b) / 3
        #expect(brightness < 0.4, "Inner edge should be dark (outline), got brightness=\(brightness)")

        try expectDominant(bitmap, at: (199, 21), channel: .b, label: "outside capsule corner should stay background")
    }

    // MARK: - Text rendering

    @Test func textShapeRendersInExport() throws {
        var row = makeTestRow(width: 400, height: 400, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 400, height: 400,
            color: Color(red: 0.9, green: 0, blue: 0),
            text: "WWWW\nWWWW\nWWWW", fontSize: 80, fontWeight: 700
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        try expectHasNonWhitePixel(bitmap, label: "Text should render visible pixels in export")
    }

    @Test func textShapeWithTrackingRendersInExport() throws {
        var row = makeTestRow(width: 400, height: 400, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 400, height: 400,
            color: Color(red: 0.9, green: 0, blue: 0),
            text: "WWWW\nWWWW\nWWWW", fontSize: 80, fontWeight: 700,
            letterSpacing: 5
        )]
        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        try expectHasNonWhitePixel(bitmap, label: "Text with tracking should render in export")
    }

    // MARK: - Helpers

    private static let testBlue = Color(red: 0, green: 0, blue: 0.9)
    private static let testRed = Color(red: 0.9, green: 0, blue: 0)

    private func makeTestRow(
        width: CGFloat = 200,
        height: CGFloat = 400,
        templateCount: Int = 1,
        bgColor: Color = .blue
    ) -> ScreenshotRow {
        ScreenshotRow(
            templates: (0..<templateCount).map { _ in ScreenshotTemplate() },
            templateWidth: width,
            templateHeight: height,
            bgColor: bgColor
        )
    }

    /// Creates a 400×800 two-template row with a red background and one transparent
    /// shape whose position/size are expressed as fractions of the template dimensions.
    private func makeOversizedShapeRow(
        shapeX: CGFloat, shapeY: CGFloat, shapeW: CGFloat, shapeH: CGFloat
    ) -> (row: ScreenshotRow, tw: CGFloat, th: CGFloat) {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            bgColor: .red
        )
        row.shapes = [CanvasShapeModel(
            type: .rectangle,
            x: tw * shapeX, y: th * shapeY,
            width: tw * shapeW, height: th * shapeH,
            color: .clear, opacity: 0
        )]
        return (row, tw, th)
    }

    private func renderTemplateBitmap(index: Int, row: ScreenshotRow) throws -> NSBitmapImageRep {
        let image = ExportService.renderTemplateImage(index: index, row: row)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        return try #require(NSBitmapImageRep(data: pngData))
    }

    private struct PixelRGB {
        let r: CGFloat, g: CGFloat, b: CGFloat
    }

    private enum Channel { case r, g, b }

    private func pixelColor(_ bitmap: NSBitmapImageRep, at point: (Int, Int)) throws -> PixelRGB {
        let color = try #require(bitmap.colorAt(x: point.0, y: point.1), "No color at (\(point.0),\(point.1))")
        let srgb = try #require(color.usingColorSpace(.sRGB), "Cannot convert to sRGB")
        return PixelRGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }

    /// Asserts that the given channel is the dominant one at a pixel, tolerant of color-space shifts.
    private func expectDominant(
        _ bitmap: NSBitmapImageRep,
        at point: (Int, Int),
        channel: Channel,
        margin: CGFloat = 0.15,
        label: String
    ) throws {
        let c = try pixelColor(bitmap, at: point)
        switch channel {
        case .r:
            #expect(c.r > c.g + margin && c.r > c.b + margin,
                    "\(label): red should dominate, got rgb=(\(c.r),\(c.g),\(c.b))")
        case .g:
            #expect(c.g > c.r + margin && c.g > c.b + margin,
                    "\(label): green should dominate, got rgb=(\(c.r),\(c.g),\(c.b))")
        case .b:
            #expect(c.b > c.r + margin && c.b > c.g + margin,
                    "\(label): blue should dominate, got rgb=(\(c.r),\(c.g),\(c.b))")
        }
    }

    /// Scans a grid of pixels and asserts at least one is non-white (i.e. visible content was rendered).
    private func expectHasNonWhitePixel(_ bitmap: NSBitmapImageRep, label: String) throws {
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        for y in stride(from: h / 8, to: h * 7 / 8, by: 20) {
            for x in stride(from: w / 8, to: w * 7 / 8, by: 20) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.r < 0.95 || c.g < 0.95 || c.b < 0.95 { return }
            }
        }
        Issue.record("\(label): all sampled pixels were white")
    }

}
