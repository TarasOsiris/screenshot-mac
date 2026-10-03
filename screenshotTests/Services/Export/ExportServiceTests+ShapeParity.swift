import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension ExportServiceTests {
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

    /// An image shape's outline must render in export: the edge band takes the outline color
    /// while the interior stays the image content, and an outlined image differs from a plain one.
    @Test func imageOutlineRendersInExport() throws {
        let tw: CGFloat = 500, th: CGFloat = 1000
        func row(withOutline: Bool) -> ScreenshotRow {
            var r = makeTestRow(width: tw, height: th, bgColor: .white)
            var image = CanvasShapeModel(
                type: .image, x: 120, y: 220, width: 200, height: 300,
                color: .clear, imageFileName: "pic"
            )
            image.outlineColor = withOutline ? .red : nil
            image.outlineWidth = withOutline ? 20 : nil
            r.shapes = [image]
            return r
        }
        let images = ["pic": makeSolidImage(.green, width: 400, height: 600)]

        let outlined = try renderTemplateBitmap(index: 0, row: row(withOutline: true), screenshotImages: images)
        let plain = try renderTemplateBitmap(index: 0, row: row(withOutline: false), screenshotImages: images)
        try expectBitmapsDiffer(outlined, plain, label: "image outline vs none")

        // Image spans x120..320, y220..520 with a 20px band. Left edge is outline (red),
        // center is the image (green — not red).
        try expectDominant(outlined, at: (126, 370), channel: .r, label: "image outline edge")
        try expectDominant(outlined, at: (220, 370), channel: .g, label: "image outline interior")
        try expectDominant(plain, at: (126, 370), channel: .g, label: "plain image edge")
    }

    /// An image whose aspect ratio differs from its shape's must be cropped to the shape, not
    /// merely centered in it: `.aspectRatio(.fill)` resolves to the *overflowing* size, so a clip
    /// applied before the shape-bounds frame crops nothing and the content spills over its
    /// neighbours. The outline follows the same rect and would land on the overflow instead.
    @Test func aspectFillImageStaysInsideShapeBoundsInExport() throws {
        let tw: CGFloat = 500, th: CGFloat = 1000
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var image = CanvasShapeModel(
            type: .image, x: 150, y: 400, width: 200, height: 100,
            color: .clear, imageFileName: "pic"
        )
        image.outlineColor = Self.testRed
        image.outlineWidth = 10
        row.shapes = [image]
        // Square source in a 2:1 shape — `.fill` scales it to 200×200, so 50px would spill
        // above and below the shape's 400..500 band.
        let images = ["pic": makeSolidImage(.green, width: 400, height: 400)]

        let bmp = try renderTemplateBitmap(index: 0, row: row, screenshotImages: images)

        try expectNearWhite(bmp, at: (250, 375), label: "20px above the image shape")
        try expectNearWhite(bmp, at: (250, 525), label: "20px below the image shape")
        try expectDominant(bmp, at: (250, 450), channel: .g, label: "image shape interior")
        try expectDominant(bmp, at: (250, 404), channel: .r, label: "outline band at the shape's top edge")
    }

    /// An image shape with no image assigned is an editor affordance only. Export and preview
    /// must render nothing for it — not the gray plate the editor shows, and not its outline.
    @Test func emptyImageShapeRendersNothingInExport() throws {
        let tw: CGFloat = 400, th: CGFloat = 800
        var row = makeTestRow(width: tw, height: th, bgColor: .white)
        var image = CanvasShapeModel(
            type: .image, x: 100, y: 200, width: 200, height: 300,
            color: .clear
        )
        image.outlineColor = Self.testRed
        image.outlineWidth = 10
        row.shapes = [image]
        let shapeRect = CGRect(x: 100, y: 200, width: 200, height: 300)

        for (pathLabel, bmp) in [
            ("renderTemplateImage", try renderTemplateBitmap(index: 0, row: row)),
            ("renderSingleTemplateImage (Preview)", try renderSingleTemplateBitmap(index: 0, row: row)),
        ] {
            for point in [(150, 250), (200, 350), (250, 450), (105, 205), (295, 495)] {
                try expectNearWhite(bmp, at: point, label: "\(pathLabel): empty image shape at \(point)")
            }
        }

        // The editor still shows the placeholder — that asymmetry is the point.
        let editor = try renderEditorBitmap(index: 0, row: row)
        try expectHasNonWhitePixel(editor, region: shapeRect, label: "editor placeholder for an empty image shape")
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
}
