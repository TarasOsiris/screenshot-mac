import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

extension ExportServiceTests {
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

    @Test func textShapeRendersInEditorCanvas() throws {
        let row = makeEditorTextRow()
        let bitmap = try renderEditorBitmap(index: 0, row: row)
        try expectHasNonWhitePixel(bitmap, label: "Text should render visible pixels in editor")
    }

    @Test func textShapeKeepsEditorBackgroundCleanOutsideGlyphs() throws {
        let row = makeEditorTextRow()
        let editorBitmap = try renderEditorBitmap(index: 0, row: row)
        try expectNearWhite(editorBitmap, at: (20, 20), label: "Editor top-left should stay background")
        try expectNearWhite(editorBitmap, at: (380, 380), label: "Editor bottom-right should stay background")
    }

    /// Shrink-to-fit changes what the text raster draws, so it must reach export through the same
    /// raster the editor uses — and change the result against the unshrunk shape.
    @Test func shrinkToFitTextMatchesEditorAndExport() throws {
        func row(shrink: Bool) -> ScreenshotRow {
            var row = makeTestRow(width: 400, height: 400, bgColor: .white)
            var shape = CanvasShapeModel(
                type: .text, x: 0, y: 0, width: 400, height: 120,
                color: Color(red: 0.9, green: 0, blue: 0),
                text: "WWWW WWWW WWWW", fontSize: 80, fontWeight: 700
            )
            shape.shrinkToFit = shrink
            row.shapes = [shape]
            return row
        }
        let shrunkExport = try renderTemplateBitmap(index: 0, row: row(shrink: true))
        let shrunkEditor = try renderEditorBitmap(index: 0, row: row(shrink: true))
        let plainExport = try renderTemplateBitmap(index: 0, row: row(shrink: false))

        let exportInk = try inkPixelCount(shrunkExport)
        let editorInk = try inkPixelCount(shrunkEditor)
        #expect(exportInk > 0)
        // The editor rasterizes text at 1×, export at 2×, so edge antialiasing alone moves the count a few percent.
        #expect(abs(exportInk - editorInk) <= max(20, exportInk * 15 / 100), "editor \(editorInk) vs export \(exportInk)")
        #expect(abs(exportInk - (try inkPixelCount(plainExport))) > exportInk / 10, "Shrinking must change what is drawn")
    }

    func makeHeadlineRow(_ configure: (inout CanvasShapeModel) -> Void) -> ScreenshotRow {
        var row = makeTestRow(width: 400, height: 400, bgColor: .white)
        var shape = CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 400, height: 400,
            color: .black, text: "WWW\nWWW", fontSize: 120, fontWeight: 900
        )
        configure(&shape)
        row.shapes = [shape]
        return row
    }

    /// The outline is drawn outside the glyphs, so the unoutlined render's paper turns stroke-colored
    /// right at the glyph edges, and editor and export agree.
    @Test func textOutlineRendersOutsideTheGlyphsInEditorAndExport() throws {
        let outlined = makeHeadlineRow {
            $0.outlineColorData = CodableColor(Color(red: 0, green: 0, blue: 0.9))
            $0.outlineWidth = 6
        }
        let exportBitmap = try renderTemplateBitmap(index: 0, row: outlined)
        let editorBitmap = try renderEditorBitmap(index: 0, row: outlined)
        let plain = try renderTemplateBitmap(index: 0, row: makeHeadlineRow { _ in })

        func bluePixels(_ bitmap: NSBitmapImageRep) throws -> Int {
            var count = 0
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                    let c = try pixelColor(bitmap, at: (x, y))
                    if c.b > 0.6 && c.r < 0.4 && c.g < 0.4 { count += 1 }
                }
            }
            return count
        }
        let exportBlue = try bluePixels(exportBitmap)
        #expect(exportBlue > 100, "The outline should be visible in export")
        #expect(try bluePixels(plain) == 0)
        let editorBlue = try bluePixels(editorBitmap)
        #expect(abs(exportBlue - editorBlue) <= max(40, exportBlue * 20 / 100), "editor \(editorBlue) vs export \(exportBlue)")
    }

    @Test func textGradientFillVariesAcrossTheGlyphs() throws {
        let row = makeHeadlineRow {
            $0.fillStyle = .gradient
            $0.fillGradientConfig = GradientConfig(
                stops: [
                    GradientColorStop(color: Color(red: 1, green: 0, blue: 0), location: 0),
                    GradientColorStop(color: Color(red: 0, green: 0, blue: 1), location: 1),
                ],
                angle: 90
            )
        }
        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        var reds = 0, blues = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.r > 0.7 && c.b < 0.4 && c.g < 0.4 { reds += 1 }
                if c.b > 0.7 && c.r < 0.4 && c.g < 0.4 { blues += 1 }
            }
        }
        #expect(reds > 50 && blues > 50, "red \(reds), blue \(blues)")
        try expectNearWhite(bitmap, at: (2, 2), label: "Paper outside the glyphs stays clear of the gradient")
    }

    /// A zoomed, panned crop shows the chosen quadrant in export, identically in the editor, and
    /// never lets the picture spill past the shape.
    @Test func imageCropShowsThePannedQuadrantInEditorAndExport() throws {
        let quadrants = makeQuadrantImage()
        var row = makeTestRow(width: 400, height: 400, bgColor: .white)
        var shape = CanvasShapeModel(type: .image, x: 100, y: 100, width: 200, height: 200)
        shape.imageFileName = "quad.png"
        // 2× with the picture pushed right and down as far as it goes: the top-left quadrant fills the frame.
        shape.imageCrop = ImageCrop(scale: 2, offsetX: 0.5, offsetY: 0.5)
        row.shapes = [shape]
        let images = ["quad.png": quadrants]

        let export = try renderTemplateBitmap(index: 0, row: row, screenshotImages: images)
        let editor = try renderEditorBitmap(index: 0, row: row, screenshotImages: images)
        for bitmap in [export, editor] {
            try expectDominant(bitmap, at: (130, 130), channel: .r, label: "top-left of frame")
            try expectDominant(bitmap, at: (270, 270), channel: .r, label: "bottom-right of frame")
            try expectNearWhite(bitmap, at: (90, 90), label: "outside the shape")
            try expectNearWhite(bitmap, at: (310, 310), label: "outside the shape")
        }
    }

    func makeQuadrantImage() -> NSImage {
        let size = NSSize(width: 200, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        // AppKit's origin is bottom-left: y >= 100 is the top half.
        NSColor(srgbRed: 0.9, green: 0, blue: 0, alpha: 1).setFill(); NSRect(x: 0, y: 100, width: 100, height: 100).fill()
        NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1).setFill(); NSRect(x: 100, y: 100, width: 100, height: 100).fill()
        NSColor(srgbRed: 0, green: 0, blue: 0.9, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 100, height: 100).fill()
        NSColor(srgbRed: 0.9, green: 0.6, blue: 0, alpha: 1).setFill(); NSRect(x: 100, y: 0, width: 100, height: 100).fill()
        image.unlockFocus()
        return image
    }

    func inkPixelCount(_ bitmap: NSBitmapImageRep) throws -> Int {
        var count = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.g < 0.5 { count += 1 }
            }
        }
        return count
    }
}
