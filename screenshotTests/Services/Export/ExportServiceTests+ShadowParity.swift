import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension ExportServiceTests {
    @Test func deviceShadowChangesExportOutput() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        func row(withShadow: Bool) -> ScreenshotRow {
            var r = makeTestRow(width: tw, height: th, bgColor: .white)
            var device = CanvasShapeModel(
                type: .device, x: 120, y: 150, width: 160, height: 420,
                color: .clear, deviceCategory: .iphone
            )
            device.shadow = withShadow ? .strong : nil
            r.shapes = [device]
            return r
        }

        let shadowed = try renderTemplateBitmap(index: 0, row: row(withShadow: true))
        let plain = try renderTemplateBitmap(index: 0, row: row(withShadow: false))

        try expectBitmapsDiffer(shadowed, plain, label: "device shadow vs none")
    }

    @Test func deviceShadowExportMatchesEditor() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 120, y: 150, width: 160, height: 420,
            color: .clear, deviceCategory: .iphone
        )
        device.shadow = .strong
        row.shapes = [device]

        let exportBitmap = try renderTemplateBitmap(index: 0, row: row)
        let editorBitmap = try renderEditorBitmap(index: 0, row: row)

        // Device normalizes to ~x120..313, y150..570. Sample the soft shadow halo
        // (below / to the sides, outside the body) plus plain background. We avoid the
        // device's high-contrast bezel edge, where sub-pixel anti-aliasing legitimately
        // differs between the full-row-crop and separate-flatten compositing paths.
        for (label, x, y) in [
            ("shadow below", 216, 610),
            ("shadow below-lower", 216, 660),
            ("shadow left halo", 95, 360),
            ("shadow right halo", 340, 360),
            ("plain background", 20, 20),
        ] {
            try expectPixelsClose(exportBitmap, editorBitmap, at: (x, y), tolerance: 0.04,
                                  label: label)
        }
    }

    @Test func singleTemplateRendererIncludesShadowFromNeighboringTemplate() throws {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, templateCount: 2, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 220, y: 210, width: 160, height: 360,
            color: .clear, deviceCategory: .iphone
        )
        device.shadow = ShadowConfig(
            enabled: true,
            color: .black,
            radius: 45,
            offsetX: 65,
            offsetY: 0,
            opacity: 0.55
        )
        row.shapes = [device]

        let fullExport = try renderTemplateBitmap(index: 1, row: row)
        let singleTemplate = try renderSingleTemplateBitmap(index: 1, row: row)

        for (label, x, y) in [
            ("shadow crossing left edge", 22, 380),
            ("shadow crossing mid-left", 50, 380),
            ("plain background", 360, 40),
        ] {
            try expectPixelsClose(fullExport, singleTemplate, at: (x, y), tolerance: 0.04, label: label)
        }
    }

    /// The drop shadow must fall BELOW the device (positive Y offset), matching the
    /// live canvas. Guards against a regression where it rendered above/flipped.
    @Test func deviceShadowFallsBelowDeviceInExport() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 120, y: 220, width: 160, height: 380,
            color: .clear, deviceCategory: .iphone
        )
        device.shadow = .strong
        row.shapes = [device]
        // Check BOTH export paths: full row export and the single-template renderer
        // used by the "Preview" (QuickLook) button.
        for (pathLabel, bmp) in [
            ("renderTemplateImage", try renderTemplateBitmap(index: 0, row: row)),
            ("renderSingleTemplateImage (Preview)", try renderSingleTemplateBitmap(index: 0, row: row)),
        ] {
            let above = try pixelColor(bmp, at: (200, 150))
            let below = try pixelColor(bmp, at: (200, 660))
            let aboveBright = (above.r + above.g + above.b) / 3
            let belowBright = (below.r + below.g + below.b) / 3
            #expect(belowBright < aboveBright - 0.02,
                    "\(pathLabel): shadow should darken below the device, not above: above=\(aboveBright) below=\(belowBright)")
        }
    }

    /// The drop shadow is generic across shape types — a non-device shape (rectangle)
    /// must change export output when enabled, and its halo must fall BELOW the shape
    /// (positive Y offset), proving the editor↔export Y-flip compensation holds for
    /// shapes that are not devices.
    @Test func nonDeviceShapeShadowFallsBelowInExport() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        func row(withShadow: Bool) -> ScreenshotRow {
            var r = makeTestRow(width: tw, height: th, bgColor: .white)
            var rect = CanvasShapeModel(
                type: .rectangle, x: 120, y: 220, width: 160, height: 200,
                color: .blue
            )
            rect.shadow = withShadow ? .strong : nil
            r.shapes = [rect]
            return r
        }

        let shadowed = try renderTemplateBitmap(index: 0, row: row(withShadow: true))
        let plain = try renderTemplateBitmap(index: 0, row: row(withShadow: false))
        try expectBitmapsDiffer(shadowed, plain, label: "rectangle shadow vs none")

        // Rect spans ~y220..420. Sample background above vs below the body.
        let above = try pixelColor(shadowed, at: (200, 180))
        let below = try pixelColor(shadowed, at: (200, 470))
        let aboveBright = (above.r + above.g + above.b) / 3
        let belowBright = (below.r + below.g + below.b) / 3
        #expect(belowBright < aboveBright - 0.02,
                "rectangle shadow should darken below the shape, not above: above=\(aboveBright) below=\(belowBright)")
    }

    /// The built-in ambient shadows (showcase tiles, abstract device bodies) go through
    /// `flipCompensatedShadow`, which must keep the halo below the shape in offscreen
    /// renders the same way `ShadowModifier` does for the configurable shadows.
    @Test func flipCompensatedShadowFallsBelowInOffscreenRender() throws {
        let size: CGFloat = 300
        let view = ZStack(alignment: .topLeading) {
            Color.white
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue)
                .frame(width: 100, height: 100)
                .flipCompensatedShadow(color: .black.opacity(0.6), radius: 12, y: 20)
                .position(x: 150, y: 150)
        }
        .frame(width: size, height: size)

        let image = RowRenderer.renderViewToImage(view, width: size, height: size, label: "flip-compensated shadow")
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        let bmp = try #require(NSBitmapImageRep(data: pngData))

        // Shape spans y 100–200; sample the background 20px above and below it.
        let above = try pixelColor(bmp, at: (150, 80))
        let below = try pixelColor(bmp, at: (150, 220))
        let aboveBright = (above.r + above.g + above.b) / 3
        let belowBright = (below.r + below.g + below.b) / 3
        #expect(belowBright < aboveBright - 0.02,
                "ambient shadow should darken below the shape offscreen, not above: above=\(aboveBright) below=\(belowBright)")
    }

    /// Same as above but for a real image-based (bezel PNG) frame with a screenshot —
    /// the multi-sub-layer case that actually triggered the editor↔preview mismatch.
    /// Sensitive to the `.compositingGroup()` fix.
    @Test func imageFrameDeviceShadowFallsBelowInExport() throws {
        let tw: CGFloat = 500, th: CGFloat = 1000
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 150, y: 220, width: 200, height: 520,
            color: .clear, deviceCategory: .iphone,
            deviceFrameId: "iphone17-black-portrait",
            screenshotFileName: "shot"
        )
        device.shadow = .strong
        row.shapes = [device]
        let images = ["shot": makeSolidImage(.white, width: 1206, height: 2622)]
        for (pathLabel, bmp) in [
            ("renderTemplateImage", try renderTemplateBitmap(index: 0, row: row, screenshotImages: images)),
            ("renderSingleTemplateImage (Preview)", try renderSingleTemplateBitmap(index: 0, row: row, screenshotImages: images)),
        ] {
            let above = try pixelColor(bmp, at: (250, 150))
            let below = try pixelColor(bmp, at: (250, 820))
            let aboveBright = (above.r + above.g + above.b) / 3
            let belowBright = (below.r + below.g + below.b) / 3
            #expect(belowBright < aboveBright - 0.02,
                    "\(pathLabel): image-frame shadow should be below, not above: above=\(aboveBright) below=\(belowBright)")
        }
    }

    /// A ROTATED device's shadow must still fall below it in export, matching the editor.
    /// Guards the rotation-aware offscreen-flip compensation: a naive per-component
    /// Y-negation would push the shadow to the wrong side once the device is rotated.
    @Test func rotatedDeviceShadowFallsBelowInExport() throws {
        let tw: CGFloat = 500, th: CGFloat = 1000
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 150, y: 250, width: 200, height: 480,
            rotation: 35,
            color: .clear, deviceCategory: .iphone,
            deviceFrameId: "iphone17-black-portrait",
            screenshotFileName: "shot"
        )
        device.shadow = .strong
        row.shapes = [device]
        let images = ["shot": makeSolidImage(.white, width: 1206, height: 2622)]
        let bmp = try renderTemplateBitmap(index: 0, row: row, screenshotImages: images)

        // For a +35° device the compensated shadow falls to the lower-left. If the flip
        // were mishandled it would land upper-left. Compare a lower-left patch (expected
        // shadow) against the mirror-image upper-left patch (expected clean background).
        let lowerLeft = try pixelColor(bmp, at: (150, 720))
        let upperLeft = try pixelColor(bmp, at: (150, 280))
        let lowerBright = (lowerLeft.r + lowerLeft.g + lowerLeft.b) / 3
        let upperBright = (upperLeft.r + upperLeft.g + upperLeft.b) / 3
        #expect(lowerBright < upperBright - 0.02,
                "rotated shadow should fall to the lower-left, not upper-left: lower=\(lowerBright) upper=\(upperBright)")
    }

    /// The shadow must sit strictly BEHIND the device — never bleed on top of the
    /// screenshot. `.compositingGroup()` collapses the frame to one silhouette so the
    /// screenshot's own sub-layer can't cast an inner shadow. A bright screenshot
    /// fills the screen; its center must stay bright.
    @Test func deviceShadowDoesNotBleedInsideDevice() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 110, y: 140, width: 180, height: 480,
            borderRadius: 24, color: .clear, deviceCategory: .invisible,
            screenshotFileName: "screen"
        )
        device.shadow = .strong
        row.shapes = [device]
        // Bright white screenshot fills the (bezel-less) invisible frame.
        let bmp = try renderTemplateBitmap(
            index: 0, row: row,
            screenshotImages: ["screen": makeSolidImage(.white, width: 400, height: 1000)]
        )
        // Center of the device screen must remain near-white (screenshot), not darkened.
        try expectNearWhite(bmp, at: (200, 380), label: "device screen center (shadow must not bleed inside)")
    }

    /// Invisible frames must support the shadow too (bug: previously excluded).
    @Test func invisibleDeviceShadowRendersInExport() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        func row(withShadow: Bool) -> ScreenshotRow {
            var r = makeTestRow(width: tw, height: th, bgColor: .white)
            var device = CanvasShapeModel(
                type: .device, x: 120, y: 180, width: 160, height: 420,
                borderRadius: 24, color: .clear, deviceCategory: .invisible,
                screenshotFileName: "x"
            )
            device.shadow = withShadow ? .strong : nil
            r.shapes = [device]
            return r
        }
        let shadowed = try renderTemplateBitmap(
            index: 0, row: row(withShadow: true),
            screenshotImages: ["x": makeSolidImage(.blue, width: 400, height: 1000)]
        )
        let plain = try renderTemplateBitmap(
            index: 0, row: row(withShadow: false),
            screenshotImages: ["x": makeSolidImage(.blue, width: 400, height: 1000)]
        )
        try expectBitmapsDiffer(shadowed, plain, label: "invisible device shadow vs none")
    }

    /// The only scale-dependent term in the shadow is `radius/offset * displayScale`.
    /// Rendering the editor at displayScale 2.0 must produce a pixel-exact 2× scaling
    /// of the 1.0 render — i.e. the shadow at proportional location (2·mx, 2·my) equals
    /// the shadow at (mx, my). This is exactly the editor↔export parity at any zoom.
    @Test func deviceShadowScalesWithDisplayScale() throws {
        let tw: CGFloat = 300
        let th: CGFloat = 600
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var device = CanvasShapeModel(
            type: .device, x: 90, y: 110, width: 120, height: 320,
            color: .clear, deviceCategory: .iphone
        )
        device.shadow = .strong
        row.shapes = [device]

        let bitmap1x = try renderEditorBitmap(index: 0, row: row, displayScale: 1.0)
        let bitmap2x = try renderEditorBitmap(index: 0, row: row, displayScale: 2.0)

        // Device normalizes to ~x90..237, y110..430. Sample shadow-halo / background
        // points (outside the body) so the proportional comparison isn't dominated by
        // sub-pixel anti-aliasing at the high-contrast device edge.
        for (label, mx, my) in [
            ("shadow below", 160, 470),
            ("shadow below-lower", 160, 500),
            ("shadow left halo", 60, 270),
            ("shadow right halo", 270, 270),
            ("plain background", 20, 30),
        ] {
            let c1 = try pixelColor(bitmap1x, at: (mx, my))
            let c2 = try pixelColor(bitmap2x, at: (mx * 2, my * 2))
            let delta = abs(c1.r - c2.r) + abs(c1.g - c2.g) + abs(c1.b - c2.b)
            #expect(delta < 0.1, "\(label): shadow did not scale proportionally with displayScale, delta=\(delta)")
        }
    }
}
