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
            index: 0, row: row, format: .png, scale: 1.0
        ))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.hasAlpha == false)
    }

    @Test func renderTemplateDataJPEG() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(ExportService.renderTemplateData(
            index: 0, row: row, format: .jpeg, scale: 1.0
        ))
        #expect(data.count > 0)
    }

    @Test func renderTemplateAtScale2x() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(ExportService.renderTemplateData(
            index: 0, row: row, format: .png, scale: 2.0
        ))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 400)
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
        try expectRedBackground(bitmap, at: (Int(tw) / 2, Int(th) - 3), label: "bottom-center")
    }

    /// Same regression test but for the second template in a multi-template row,
    /// where the oversized shape spans from template 0 into template 1.
    @Test func oversizedShapeDoesNotShiftSecondTemplateRendering() throws {
        let (row, tw, th) = makeOversizedShapeRow(
            shapeX: 0.8, shapeY: 0, shapeW: 2.0, shapeH: 0.5
        )

        let bitmap = try renderTemplateBitmap(index: 1, row: row)

        for (label, x, y) in [("bottom-left", 2, Int(th) - 3), ("bottom-right", Int(tw) - 3, Int(th) - 3)] {
            try expectRedBackground(bitmap, at: (x, y), label: label)
        }
    }

    // MARK: - Helpers

    private func makeTestRow(width: CGFloat = 200, height: CGFloat = 400) -> ScreenshotRow {
        ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: width,
            templateHeight: height
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

    private func expectRedBackground(_ bitmap: NSBitmapImageRep, at point: (Int, Int), label: String) throws {
        let color = try #require(bitmap.colorAt(x: point.0, y: point.1), "No color at \(label)")
        let srgb = try #require(color.usingColorSpace(.sRGB), "Cannot convert \(label) to sRGB")
        #expect(srgb.redComponent > 0.5, "Expected red background at \(label), got r=\(srgb.redComponent) g=\(srgb.greenComponent) b=\(srgb.blueComponent)")
    }

}
