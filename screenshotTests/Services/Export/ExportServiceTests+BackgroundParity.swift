import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension ExportServiceTests {
    // MARK: - Export / editor parity
    //
    // These tests verify that RowRenderer.renderTemplateImage produces pixel-accurate
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

    @Test func blurredSolidBackgroundKeepsEdgesOpaque() throws {
        let tw: CGFloat = 200
        let th: CGFloat = 400
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            bgColor: Self.testRed,
            backgroundBlur: 24
        )
        let bitmap = try renderTemplateBitmap(index: 0, row: row)

        for (label, x, y) in [
            ("top-left", 2, 2), ("top-right", Int(tw) - 3, 2),
            ("bottom-left", 2, Int(th) - 3), ("bottom-right", Int(tw) - 3, Int(th) - 3),
        ] {
            try expectDominant(bitmap, at: (x, y), channel: .r, label: label)
        }
    }

    @Test func blurredSpanningGradientMatchesEditor() throws {
        let tw: CGFloat = 220
        let th: CGFloat = 220
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 90
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true,
            backgroundBlur: 24
        )

        let exportBitmap = try renderTemplateBitmap(index: 1, row: row)
        let editorBitmap = try renderEditorBitmap(index: 1, row: row)

        for (label, x, y) in [
            ("top-left", 12, 12),
            ("top-right", Int(tw) - 13, 12),
            ("center", Int(tw) / 2, Int(th) / 2),
            ("bottom-left", 12, Int(th) - 13),
            ("bottom-right", Int(tw) - 13, Int(th) - 13),
        ] {
            try expectPixelsClose(exportBitmap, editorBitmap, at: (x, y), label: label)
        }
    }

    @Test func singleTemplateRendererMatchesFullExportForBlurredSpanningBackground() throws {
        let tw: CGFloat = 220
        let th: CGFloat = 220
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 90
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true,
            backgroundBlur: 24
        )

        let singleTemplateBitmap = try renderSingleTemplateBitmap(index: 1, row: row)
        let fullExportBitmap = try renderTemplateBitmap(index: 1, row: row)

        for (label, x, y) in [
            ("top-left", 12, 12),
            ("top-right", Int(tw) - 13, 12),
            ("center", Int(tw) / 2, Int(th) / 2),
            ("bottom-left", 12, Int(th) - 13),
            ("bottom-right", Int(tw) - 13, Int(th) - 13),
        ] {
            try expectPixelsClose(singleTemplateBitmap, fullExportBitmap, at: (x, y), label: label)
        }
    }

    /// Non-blurred spanning background: the single-template renderer slices the spanning view by
    /// offset rather than building/cropping the full-row strip. That slice must be pixel-identical
    /// to the full-row export, especially at the left boundary where the spanning gradient must
    /// continue from the previous template rather than restart.
    @Test func singleTemplateRendererMatchesFullExportForSpanningGradient() throws {
        let tw: CGFloat = 220
        let th: CGFloat = 220
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 0
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true
        )

        for index in 0..<3 {
            let singleTemplateBitmap = try renderSingleTemplateBitmap(index: index, row: row)
            let fullExportBitmap = try renderTemplateBitmap(index: index, row: row)
            for (label, x, y) in [
                ("left-edge", 2, Int(th) / 2),
                ("right-edge", Int(tw) - 3, Int(th) / 2),
                ("center", Int(tw) / 2, Int(th) / 2),
            ] {
                try expectPixelsClose(singleTemplateBitmap, fullExportBitmap, at: (x, y), label: "[\(index)] \(label)")
            }
        }
    }

    @Test func blurredStepGradientChangesBoundaryPixelInExport() throws {
        let tw: CGFloat = 240
        let th: CGFloat = 240
        let sharpGradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0.49),
                GradientColorStop(color: Self.testRed, location: 0.5),
                GradientColorStop(color: Self.testBlue, location: 0.5),
                GradientColorStop(color: Self.testBlue, location: 0.51),
            ],
            angle: 90
        )

        let unblurredRow = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: sharpGradient,
            spanBackgroundAcrossRow: true,
            backgroundBlur: 0
        )
        let blurredRow = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: sharpGradient,
            spanBackgroundAcrossRow: true,
            backgroundBlur: 24
        )

        let unblurred = try renderTemplateBitmap(index: 0, row: unblurredRow)
        let blurred = try renderTemplateBitmap(index: 0, row: blurredRow)

        let x = Int(tw) - 4
        let y = Int(th) / 2
        let sharp = try pixelColor(unblurred, at: (x, y))
        let soft = try pixelColor(blurred, at: (x, y))
        let delta = abs(sharp.r - soft.r) + abs(sharp.g - soft.g) + abs(sharp.b - soft.b)
        #expect(delta > 0.12, "Blur should change the hard boundary pixel, delta=\(delta)")
    }

    @Test func compositeTemplateMatchesEditor() throws {
        let tw: CGFloat = 240
        let th: CGFloat = 240
        let gradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0),
                GradientColorStop(color: Self.testBlue, location: 1),
            ],
            angle: 90
        )
        var overriddenTemplate = ScreenshotTemplate(backgroundColor: Self.testGreen)
        overriddenTemplate.overrideBackground = true
        overriddenTemplate.backgroundStyle = .color

        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), overriddenTemplate],
            templateWidth: tw,
            templateHeight: th,
            backgroundStyle: .gradient,
            gradientConfig: gradient,
            spanBackgroundAcrossRow: true,
            backgroundBlur: 18
        )
        row.shapes = [
            CanvasShapeModel(
                type: .rectangle,
                x: 180,
                y: 80,
                width: 120,
                height: 90,
                color: Self.testRed,
                opacity: 0.85
            ),
            CanvasShapeModel(
                type: .rectangle,
                x: 260,
                y: 24,
                width: 70,
                height: 50,
                color: .white,
                clipToTemplate: true
            ),
        ]

        let exportBitmap = try renderTemplateBitmap(index: 1, row: row)
        let editorBitmap = try renderEditorBitmap(index: 1, row: row)

        for (label, x, y) in [
            ("override bg", 24, 24),
            ("shared shape", 30, 120),
            ("clipped shape", 40, 40),
            ("far corner", Int(tw) - 20, Int(th) - 20),
        ] {
            try expectPixelsClose(exportBitmap, editorBitmap, at: (x, y), label: label)
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

    @Test func blurredTemplateOverrideMatchesEditor() throws {
        let tw: CGFloat = 240
        let th: CGFloat = 240
        let sharpGradient = GradientConfig(
            stops: [
                GradientColorStop(color: Self.testRed, location: 0.49),
                GradientColorStop(color: Self.testRed, location: 0.5),
                GradientColorStop(color: Self.testBlue, location: 0.5),
                GradientColorStop(color: Self.testBlue, location: 0.51),
            ],
            angle: 90
        )

        var overriddenTemplate = ScreenshotTemplate()
        overriddenTemplate.overrideBackground = true
        overriddenTemplate.backgroundStyle = .gradient
        overriddenTemplate.gradientConfig = sharpGradient
        overriddenTemplate.backgroundBlur = 24

        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(backgroundColor: Self.testGreen), overriddenTemplate],
            templateWidth: tw,
            templateHeight: th,
            bgColor: Self.testGreen
        )

        // `renderEditorBitmap` goes through the rasterized background renderer, which the editor
        // only uses when this predicate is true. Without the check this test compares two
        // export-side renderers and stays green while the editor draws a SwiftUI `.blur` instead.
        #expect(row.hasBlurredBackground, "Editor must route this row through the rasterized path")

        let exportBitmap = try renderTemplateBitmap(index: 1, row: row)
        let editorBitmap = try renderEditorBitmap(index: 1, row: row)

        for (label, x, y) in [
            ("left edge", 12, Int(th) / 2),
            ("boundary", Int(tw) / 2, Int(th) / 2),
            ("right edge", Int(tw) - 13, Int(th) / 2),
        ] {
            try expectPixelsClose(exportBitmap, editorBitmap, at: (x, y), label: label)
        }
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

    @Test func spanningTiledImageRepeatsAcrossTemplatesWithSpacingGaps() throws {
        let tile = makePatternedTile(size: 40, redQuadrantSize: 20)
        let tileKey = "test-tile"

        let tw: CGFloat = 200
        let th: CGFloat = 200
        // tileSpacingX/Y = 1.0 ⇒ step = imgW * 2 = 80, leaving a 40-wide gap between tiles.
        // Across the 400-wide spanning row, anchors land at row x = 0, 80, 160, 240, 320 —
        // template 0 sees them at local x = 0, 80, 160; template 1 at local x = 40, 120.
        let bgConfig = BackgroundImageConfig(
            fileName: tileKey,
            fillMode: .tile,
            tileSpacingX: 1.0, tileSpacingY: 1.0,
            tileScaleX: 1.0, tileScaleY: 1.0
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            bgColor: Self.testBlue,
            backgroundStyle: .image,
            spanBackgroundAcrossRow: true,
            backgroundImageConfig: bgConfig
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row, screenshotImages: [tileKey: tile])
        let bmp1 = try renderTemplateBitmap(index: 1, row: row, screenshotImages: [tileKey: tile])

        // Template 0: red anchors at three tile origins (0, 80, 160) in the top-left quadrant.
        try expectDominant(bmp0, at: (10, 10), channel: .r, label: "t0 anchor 0")
        try expectDominant(bmp0, at: (90, 10), channel: .r, label: "t0 anchor 1")
        try expectDominant(bmp0, at: (170, 10), channel: .r, label: "t0 anchor 2")

        // Template 0: spacing gap between tiles (40-80, 120-160) shows the row's blue bgColor.
        try expectDominant(bmp0, at: (50, 10), channel: .b, label: "t0 gap shows bgColor")
        try expectDominant(bmp0, at: (130, 10), channel: .b, label: "t0 gap shows bgColor")

        // Template 1: tile grid continues — anchors land at local x = 40, 120 (row x = 240, 320).
        try expectDominant(bmp1, at: (50, 10), channel: .r, label: "t1 anchor at row 240")
        try expectDominant(bmp1, at: (130, 10), channel: .r, label: "t1 anchor at row 320")

        // Template 1: gap before the first anchor (row 200-240) → bgColor visible.
        try expectDominant(bmp1, at: (10, 10), channel: .b, label: "t1 leading gap")
    }

    @Test func nonSpanningTiledImageStartsFreshPerTemplate() throws {
        // Same tile as the spanning test, but spanBackgroundAcrossRow = false.
        // Each template's tile grid starts at its own origin, so both templates render identically.
        let tile = makePatternedTile(size: 40, redQuadrantSize: 20)
        let tileKey = "test-tile"

        let tw: CGFloat = 200
        let th: CGFloat = 200
        let bgConfig = BackgroundImageConfig(
            fileName: tileKey,
            fillMode: .tile,
            tileSpacingX: 1.0, tileSpacingY: 1.0,
            tileScaleX: 1.0, tileScaleY: 1.0
        )
        let row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: tw, templateHeight: th,
            bgColor: Self.testBlue,
            backgroundStyle: .image,
            spanBackgroundAcrossRow: false,
            backgroundImageConfig: bgConfig
        )

        let bmp0 = try renderTemplateBitmap(index: 0, row: row, screenshotImages: [tileKey: tile])
        let bmp1 = try renderTemplateBitmap(index: 1, row: row, screenshotImages: [tileKey: tile])

        // Both templates start with a red anchor at (10, 10) and show identical grids.
        for (label, bmp) in [("t0", bmp0), ("t1", bmp1)] {
            try expectDominant(bmp, at: (10, 10), channel: .r, label: "\(label) anchor 0")
            try expectDominant(bmp, at: (90, 10), channel: .r, label: "\(label) anchor 1")
            try expectDominant(bmp, at: (170, 10), channel: .r, label: "\(label) anchor 2")
            try expectDominant(bmp, at: (50, 10), channel: .b, label: "\(label) gap")
        }
    }

    /// Builds an NSImage that is `size`×`size` pixels: the top-left `redQuadrantSize`×`redQuadrantSize`
    /// region is opaque red, the rest is opaque white. Used for verifying tile anchor positions in export.
    func makePatternedTile(size: Int, redQuadrantSize: Int) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * 4, bitsPerPixel: 32
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
        NSColor.red.setFill()
        NSRect(x: 0, y: size - redQuadrantSize, width: redQuadrantSize, height: redQuadrantSize).fill()
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmap)
        return image
    }
}
