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

    // MARK: - Helpers

    private func makeTestRow(width: CGFloat = 200, height: CGFloat = 400) -> ScreenshotRow {
        ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: width,
            templateHeight: height
        )
    }

    private func makeTestImage(width: Int, height: Int) -> NSImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        )!
        let ctx = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmap)
        return image
    }
}
