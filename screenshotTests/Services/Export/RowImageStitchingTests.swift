import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Row export renders one template at a time and stitches them, so no single main-actor job has to
/// rasterize the whole row — a 30 MP row in one `renderViewToImage` hung the app for 3 s+ in 4.14
/// (Sentry SCREENSHOT-BRO-1V). The stitched image must stay the image `renderRowImage` produced.
@MainActor
struct RowImageStitchingTests {

    @Test(arguments: [false, true]) func stitchedRowMatchesSinglePassRowRender(blurred: Bool) async throws {
        let row = makeSpanningRow(blurred: blurred)
        let context = makeContext(row)

        let singlePass = try opaqueBitmap(RowRenderer.renderRowImage(row: row, screenshotImages: Self.images))
        let stitched = try opaqueBitmap(await context.stitchedRowImage())

        #expect(stitched.pixelsWide == singlePass.pixelsWide)
        #expect(stitched.pixelsHigh == singlePass.pixelsHigh)
        let diff = try pixelDifference(stitched, singlePass)
        #expect(diff.maxDelta <= 2, "max channel delta \(diff.maxDelta)")
    }

    /// The fix itself: the main actor must get a turn between templates. A single-pass render
    /// suspends at most once, after the whole row.
    @Test(arguments: [false, true]) func stitchedRowYieldsTheMainActorBetweenTemplates(blurred: Bool) async {
        let row = makeSpanningRow(blurred: blurred)
        let context = makeContext(row)

        let ticker = MainActorTicker()
        var rendering = true
        Task { @MainActor in
            while rendering {
                ticker.ticks += 1
                await Task.yield()
            }
        }
        _ = await context.stitchedRowImage()
        rendering = false

        // A blurred row also yields while slicing its background.
        #expect(ticker.ticks >= row.templates.count * (blurred ? 2 : 1))
    }

    /// The editor's blur raster and every export path build the full-row background through the
    /// sliced builder; it must match the one-pass composer, including override-only blur.
    @Test(arguments: [(16.0, 0.0), (0.0, 10.0), (16.0, 10.0)])
    func slicedComposedBackgroundMatchesOnePass(rowBlur: Double, overrideBlur: Double) async throws {
        var row = makeSpanningRow(blurred: rowBlur > 0)
        row.templates[2].backgroundBlur = overrideBlur

        let onePass = try opaqueBitmap(RowRenderer.renderComposedBackgroundImage(
            row: row, screenshotImages: Self.images, displayScale: 1, labelPrefix: "test"
        ))
        let sliced = try opaqueBitmap(await RowRenderer.renderComposedBackgroundInSlices(
            row: row, screenshotImages: Self.images, displayScale: 1, labelPrefix: "test"
        ))

        #expect(sliced.pixelsWide == onePass.pixelsWide)
        let diff = try pixelDifference(sliced, onePass)
        #expect(diff.maxDelta <= 2, "max channel delta \(diff.maxDelta)")
    }

    /// Per-template export and the upload services go through `forEachTemplate`/`prepareBackground`,
    /// so a blurred row's background must not be one uninterrupted job there either.
    @Test func forEachTemplateBuildsBlurredBackgroundInSlices() async {
        let row = makeSpanningRow(blurred: true)
        let context = makeContext(row)

        let ticker = MainActorTicker()
        var rendering = true
        Task { @MainActor in
            while rendering {
                ticker.ticks += 1
                await Task.yield()
            }
        }
        await context.forEachTemplate { _, _ in }
        rendering = false

        #expect(ticker.ticks >= row.templates.count * 2)
    }

    /// Slices only tile on whole pixels, so a fractional scale must fall back to the single pass.
    @Test func fractionalScaleFallsBackToSinglePassRender() async throws {
        let row = makeSpanningRow(blurred: false)
        let context = makeContext(row, displayScale: 0.37)

        let singlePass = try opaqueBitmap(context.rowImage())
        let stitched = try opaqueBitmap(await context.stitchedRowImage())

        #expect(stitched.pixelsWide == singlePass.pixelsWide)
        #expect(try pixelDifference(stitched, singlePass).maxDelta == 0)
    }

    /// The export flow's row-level path is what shipped the hang; it must still write one file per row.
    @Test func rowExportWritesStitchedRows() async throws {
        let row = makeSpanningRow(blurred: false)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("stitch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var cache: [String: NSImage] = [:]
        let source = EmptyDiskRenderSource()
        let result = try await ExportCoordinator.renderRows(
            [row, row], into: dir, source: source, imageCache: &cache, seedImages: Self.images
        ) { context in await context.stitchedRowImage() }

        #expect(result.fileURLs.count == 2)
        let written = try #require(NSBitmapImageRep(data: Data(contentsOf: result.fileURLs[0])))
        #expect(written.pixelsWide == Int(row.templateWidth) * row.templates.count)
        #expect(written.pixelsHigh == Int(row.templateHeight))
    }

    // MARK: - Fixtures

    private func makeSpanningRow(blurred: Bool) -> ScreenshotRow {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 200,
            templateHeight: 360,
            backgroundStyle: .gradient,
            gradientConfig: GradientConfig(
                stops: [
                    GradientColorStop(color: Color(red: 0.9, green: 0.1, blue: 0.1), location: 0),
                    GradientColorStop(color: Color(red: 0.1, green: 0.1, blue: 0.9), location: 1),
                ],
                angle: 90
            ),
            spanBackgroundAcrossRow: true,
            backgroundBlur: blurred ? 16 : 0
        )
        row.templates[2].overrideBackground = true
        row.templates[2].backgroundColor = CodableColor(Color(red: 0.2, green: 0.7, blue: 0.4))
        var crossing = CanvasShapeModel(
            type: .rectangle, x: 150, y: 60, width: 120, height: 140,
            color: .yellow
        )
        crossing.shadow = .strong
        let rotated = CanvasShapeModel(
            type: .circle, x: 330, y: 200, width: 140, height: 140,
            rotation: 30, color: .green
        )
        let text = CanvasShapeModel(
            type: .text, x: 20, y: 250, width: 560, height: 80,
            color: .white, text: "Spans every template", fontSize: 44, fontWeight: 700
        )
        var device = CanvasShapeModel(
            type: .device, x: 330, y: 20, width: 120, height: 250,
            color: .clear, deviceCategory: .iphone,
            deviceFrameId: "iphone17-black-portrait",
            screenshotFileName: "shot"
        )
        device.shadow = .strong
        row.shapes = [crossing, rotated, text, device]
        return row
    }

    private static let images = ["shot": makeSolidImage(.white, width: 1206, height: 2622)]

    private func makeContext(_ row: ScreenshotRow, displayScale: CGFloat = 1) -> RowRenderContext {
        RowRenderContext(
            row: row,
            images: Self.images,
            localeCode: nil,
            availableFontFamilies: PlatformFonts.familyNameSet,
            displayScale: displayScale,
            label: "stitch test"
        )
    }

    private func opaqueBitmap(_ image: NSImage) throws -> NSBitmapImageRep {
        let data = try #require(ExportService.opaquePNGData(from: image))
        return try #require(NSBitmapImageRep(data: data))
    }

    private func pixelDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> (maxDelta: Int, count: Int) {
        let aData = try #require(a.bitmapData)
        let bData = try #require(b.bitmapData)
        #expect(a.bytesPerRow == b.bytesPerRow)
        #expect(a.samplesPerPixel == b.samplesPerPixel)
        var maxDelta = 0
        var count = 0
        for index in 0..<(a.bytesPerRow * a.pixelsHigh) {
            let delta = abs(Int(aData[index]) - Int(bData[index]))
            if delta > 0 { count += 1 }
            maxDelta = max(maxDelta, delta)
        }
        return (maxDelta, count)
    }
}
