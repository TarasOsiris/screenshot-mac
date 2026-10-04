import AppKit
import CoreGraphics
@testable import Screenshot_Bro
import SwiftUI
import Testing

@MainActor
struct ExportServiceTests {

    // MARK: - Opaque PNG

    @Test func opaquePNGProducesValidData() throws {
        let image = makeTestImage(width: 200, height: 400)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        #expect(!pngData.isEmpty)

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
        #expect(!jpegData.isEmpty)

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

    @Test func renderTemplateDataProducesPNG() throws {
        let row = makeTestRow(width: 200, height: 400)
        let pngData = try #require(RowRenderer.renderTemplateData(index: 0, row: row, format: .png))
        #expect(!pngData.isEmpty)

        let decoded = try #require(NSBitmapImageRep(data: pngData))
        #expect(decoded.pixelsWide == 200)
        #expect(decoded.pixelsHigh == 400)
        #expect(decoded.hasAlpha == false)
    }

    @Test func renderTemplateDataPNG() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(RowRenderer.renderTemplateData(
            index: 0, row: row, format: .png
        ))
        let decoded = try #require(NSBitmapImageRep(data: data))
        #expect(decoded.hasAlpha == false)
    }

    @Test func renderTemplateDataJPEG() throws {
        let row = makeTestRow(width: 100, height: 200)
        let data = try #require(RowRenderer.renderTemplateData(
            index: 0, row: row, format: .jpeg
        ))
        #expect(!data.isEmpty)
    }

    /// A text shape persisted as rich text (Base64-RTF) must render through the export path —
    /// the same path the iPad editor now feeds. Guards that rich-text glyphs aren't dropped.
    @Test func renderTemplateDrawsRichTextShape() throws {
        var row = makeTestRow(width: 200, height: 200, bgColor: .white)
        let attributed = NSMutableAttributedString(string: "WWW", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 60),
            .foregroundColor: NSColor.black
        ])
        var shape = CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 200, height: 200,
            color: .black, text: "WWW", fontSize: 60
        )
        shape.richText = RichTextUtils.encode(attributed)
        row.shapes = [shape]

        let bmp = try renderTemplateBitmap(index: 0, row: row)
        // White-only output would mean the rich-text glyphs were dropped; scan the center band.
        var foundDark = false
        outer: for y in [80, 100, 120] {
            for x in stride(from: 20, to: 180, by: 4) {
                let p = try pixelColor(bmp, at: (x, y))
                if (p.r + p.g + p.b) / 3 < 0.5 { foundDark = true; break outer }
            }
        }
        #expect(foundDark, "Rich-text shape should render visible glyphs in export")
    }

    /// `availableFontFamilies` must reach the renderer. A shape whose `fontName` is a real
    /// installed family only renders in that face when the set contains it — several export
    /// call sites used to drop the argument, silently exporting custom fonts in the system face.
    @Test func renderForwardsAvailableFontFamilies() throws {
        var row = makeTestRow(width: 200, height: 200, bgColor: .white)
        var shape = CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 200, height: 200,
            color: .black, text: "MMM", fontSize: 60
        )
        shape.fontName = "Courier New"
        row.shapes = [shape]

        let named = try #require(RowRenderer.renderTemplateData(
            index: 0, row: row, format: .png, availableFontFamilies: ["Courier New"]
        ))
        let unavailable = try #require(RowRenderer.renderTemplateData(
            index: 0, row: row, format: .png, availableFontFamilies: []
        ))
        #expect(named != unavailable, "renderTemplateData must forward availableFontFamilies")
    }

    @Test func renderTemplateDrawsTextBackground() throws {
        var row = makeTestRow(width: 200, height: 200, bgColor: Self.testBlue)
        var shape = CanvasShapeModel(
            type: .text, x: 50, y: 50, width: 100, height: 100,
            color: .white, text: "Hi", fontSize: 30
        )
        shape.textBackgroundColor = Self.testRed
        shape.textBackgroundCornerRadius = 0
        row.shapes = [shape]

        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        // The red plate fills the text frame (50,50)-(150,150)…
        try expectDominant(bitmap, at: (60, 60), channel: .r, label: "text background plate")
        // …and the blue template background shows outside it.
        try expectDominant(bitmap, at: (10, 10), channel: .b, label: "outside text shape")
    }

    @Test func textBackgroundPaddingExpandsPlateBeyondFrame() throws {
        var row = makeTestRow(width: 200, height: 200, bgColor: Self.testBlue)
        var shape = CanvasShapeModel(
            type: .text, x: 50, y: 50, width: 100, height: 100,
            color: .white, text: "Hi", fontSize: 30
        )
        shape.textBackgroundColor = Self.testRed
        shape.textBackgroundPadding = 30
        row.shapes = [shape]

        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        // (30,100) is outside the text frame (x<50) but inside the padded plate (20…180) → red.
        try expectDominant(bitmap, at: (30, 100), channel: .r, label: "padded plate")
        // (5,100) is beyond the padded plate → still the blue template background.
        try expectDominant(bitmap, at: (5, 100), channel: .b, label: "beyond padded plate")
    }

    @Test func textBackgroundOutlineRendersInsidePlate() throws {
        var row = makeTestRow(width: 200, height: 200, bgColor: Self.testBlue)
        var shape = CanvasShapeModel(
            type: .text, x: 50, y: 50, width: 100, height: 100,
            color: .white, text: "", fontSize: 30
        )
        shape.textBackgroundColor = Self.testRed
        shape.textBackgroundOutlineColor = Self.testGreen
        shape.textBackgroundOutlineWidth = 10
        row.shapes = [shape]

        let bitmap = try renderTemplateBitmap(index: 0, row: row)
        try expectDominant(bitmap, at: (55, 100), channel: .g, label: "text background outline")
        try expectDominant(bitmap, at: (70, 100), channel: .r, label: "text background fill inside outline")
        try expectDominant(bitmap, at: (45, 100), channel: .b, label: "outside outlined plate")
    }

    @Test func textBackgroundOpacityDimsPlate() throws {
        func redInsidePlate(opacity: Double?) throws -> CGFloat {
            var row = makeTestRow(width: 200, height: 200, bgColor: Self.testBlue)
            var shape = CanvasShapeModel(
                type: .text, x: 50, y: 50, width: 100, height: 100,
                color: .white, text: "", fontSize: 30
            )
            shape.textBackgroundColor = Self.testRed
            shape.textBackgroundOpacity = opacity
            row.shapes = [shape]
            let bitmap = try renderTemplateBitmap(index: 0, row: row)
            return try pixelColor(bitmap, at: (100, 100)).r
        }

        let opaqueRed = try redInsidePlate(opacity: 1.0)
        let dimmedRed = try redInsidePlate(opacity: 0.3)
        // A translucent plate blends toward the blue template background, so its red channel drops.
        #expect(dimmedRed < opaqueRed - 0.2,
                "Lower textBackgroundOpacity should dim the plate: opaque=\(opaqueRed), dimmed=\(dimmedRed)")
    }

    // MARK: - Filename sanitization

    @Test func sanitizedFileNameReplacesFilesystemReservedCharacters() {
        // Path separators, Windows-reserved chars, and control bytes collapse to single underscores.
        #expect(ExportFileNaming.sanitizedFileName("a/b\\c:d*e?f\"g<h>i|j") == "a_b_c_d_e_f_g_h_i_j")
        #expect(ExportFileNaming.sanitizedFileName("line1\nline2\tx") == "line1_line2_x")
    }

    @Test func sanitizedFileNameKeepsUnicodeAndSpaces() {
        // Spaces, em-dash, accented characters, and emoji are valid on macOS — keep them.
        #expect(ExportFileNaming.sanitizedFileName("Onboarding — Привет 🎉") == "Onboarding — Привет 🎉")
    }

    @Test func sanitizedFileNameTrimsEdgeSeparators() {
        #expect(ExportFileNaming.sanitizedFileName("  ..Hello..  ") == "Hello")
        #expect(ExportFileNaming.sanitizedFileName("/leading and trailing/") == "leading and trailing")
    }

    @Test func exportRowFileNameComponentFallsBackWhenLabelEmpty() {
        var row = makeTestRow()
        row.label = ""
        // displayLabel becomes "Untitled Row", sanitized stays the same.
        #expect(ExportFileNaming.exportRowFileNameComponent(for: row) == "Untitled Row")

        row.label = "///"
        // Sanitizes away entirely → fallback "row".
        #expect(ExportFileNaming.exportRowFileNameComponent(for: row) == "row")
    }

    @Test func exportRowFileNameComponentSanitizesPathSeparators() {
        var row = makeTestRow()
        row.label = "Home / Screen 1"
        #expect(ExportFileNaming.exportRowFileNameComponent(for: row) == "Home _ Screen 1")
    }

    /// The App Store Connect and Google Play uploads name files through this same helper, so two
    /// locales of one row must not produce the same name, and the export suffix must survive.
    @Test func screenshotFileNameSeparatesLocalesAndKeepsSuffix() {
        var row = makeTestRow()
        row.label = "Onboarding"
        #expect(ExportFileNaming.screenshotFileName(row: row, localeCode: "en", index: 0) == "01_Onboarding_en.png")
        #expect(ExportFileNaming.screenshotFileName(row: row, localeCode: "de", index: 0) == "01_Onboarding_de.png")
        #expect(ExportFileNaming.screenshotFileName(row: row, localeCode: "en", index: 1, customSuffix: "v2")
                == "02_Onboarding_en_v2.png")
    }

    @Test func projectPrefixedFolderNamePrefixesTheSanitizedProjectName() {
        #expect(ExportFileNaming.projectPrefixedFolderName("showcase", projectName: "My App") == "My App showcase")
        #expect(ExportFileNaming.projectPrefixedFolderName("rows", projectName: " Trailing ") == "Trailing rows")
        #expect(ExportFileNaming.projectPrefixedFolderName("showcase", projectName: "a/b") == "a_b showcase")
    }

    /// A name with nothing usable left must not leave the folder called `" showcase"` or `"_ showcase"`.
    @Test func projectPrefixedFolderNameFallsBackToTheBareKind() {
        #expect(ExportFileNaming.projectPrefixedFolderName("showcase", projectName: "") == "showcase")
        #expect(ExportFileNaming.projectPrefixedFolderName("showcase", projectName: "   ") == "showcase")
        #expect(ExportFileNaming.projectPrefixedFolderName("showcase", projectName: "///") == "showcase")
    }

    /// Project names run to 100 characters; in emoji that is ~400 bytes, past the 255-byte limit on
    /// one path component — `createDirectory` would throw and the export would fail.
    @Test func projectPrefixedFolderNameStaysWithinThePathComponentByteLimit() {
        let name = String(repeating: "\u{1F600}", count: AppState.maxProjectNameLength)
        let folder = ExportFileNaming.projectPrefixedFolderName("showcase", projectName: name)
        #expect(folder.utf8.count < 255)
        #expect(folder.hasSuffix(" showcase"))
        #expect(folder.allSatisfy { $0 == "\u{1F600}" || " showcase".contains($0) }, "must not split a character")
    }

    @Test func preferredCustomSuffixReadsTheExportSetting() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: AppSettingsKeys.exportCustomSuffix)
        defer {
            if let previous { defaults.set(previous, forKey: AppSettingsKeys.exportCustomSuffix) }
            else { defaults.removeObject(forKey: AppSettingsKeys.exportCustomSuffix) }
        }
        defaults.set("promo", forKey: AppSettingsKeys.exportCustomSuffix)
        #expect(ExportFileNaming.preferredCustomSuffix == "promo")
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

    // MARK: - Helpers

    static let testBlue = Color(red: 0, green: 0, blue: 0.9)
    static let testRed = Color(red: 0.9, green: 0, blue: 0)
    static let testGreen = Color(red: 0, green: 0.8, blue: 0)

    func makeEditorTextRow() -> ScreenshotRow {
        var row = makeTestRow(width: 400, height: 400, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .text, x: 0, y: 0, width: 400, height: 400,
            color: Color(red: 0.9, green: 0, blue: 0),
            text: "WWWW\nWWWW\nWWWW", fontSize: 80, fontWeight: 700,
            letterSpacing: 5
        )]
        return row
    }

    /// Creates a 400×800 two-template row with a red background and one transparent
    /// shape whose position/size are expressed as fractions of the template dimensions.
    func makeOversizedShapeRow(
        shapeX: CGFloat, shapeY: CGFloat, shapeW: CGFloat, shapeH: CGFloat
    ) -> (row: ScreenshotRow, tw: CGFloat, th: CGFloat) {
        let tw: CGFloat = 400
        let th: CGFloat = 800
        let row = makeTestRow(width: tw, height: th, templateCount: 2, bgColor: .red, shapes: [CanvasShapeModel(
            type: .rectangle,
            x: tw * shapeX, y: th * shapeY,
            width: tw * shapeW, height: th * shapeH,
            color: .clear, opacity: 0
        )])
        return (row, tw, th)
    }

    func renderTemplateBitmap(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:]
    ) throws -> NSBitmapImageRep {
        let image = RowRenderer.renderTemplateImage(index: index, row: row, screenshotImages: screenshotImages)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        return try #require(NSBitmapImageRep(data: pngData))
    }

    func renderSingleTemplateBitmap(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:]
    ) throws -> NSBitmapImageRep {
        let image = RowRenderer.renderSingleTemplateImage(index: index, row: row, screenshotImages: screenshotImages)
        let pngData = try #require(ExportService.opaquePNGData(from: image))
        return try #require(NSBitmapImageRep(data: pngData))
    }

    func renderEditorBitmap(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        displayScale: CGFloat = 1.0
    ) throws -> NSBitmapImageRep {
        let tLeft = CGFloat(index) * row.templateWidth * displayScale
        let totalWidth = row.templateWidth * displayScale * CGFloat(row.templates.count)
        let composedBackground = RowRenderer.renderComposedBackgroundImage(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale,
            labelPrefix: "test editor"
        )

        // Same layer the editor and export both build; only `showsEditorHelpers` differs,
        // which is this helper's whole point.
        let shapesView = PresentationShapeLayerView(
            row: row,
            shapes: row.activeShapes,
            images: screenshotImages,
            displayScale: displayScale,
            defaultDeviceBodyColor: row.defaultDeviceBodyColor,
            availableFontFamilies: Set(NSFontManager.shared.availableFontFamilies),
            showsEditorHelpers: true
        )

        let shapesImage = RowRenderer.renderViewToImage(
            shapesView,
            width: totalWidth,
            height: row.templateHeight * displayScale,
            label: "test editor shapes"
        )
        let image = RowRenderer.flattenImage(
            shapesImage,
            over: composedBackground,
            width: totalWidth,
            height: row.templateHeight * displayScale
        )
        let cropped = try cropBitmap(image, x: tLeft, width: row.templateWidth * displayScale, height: row.templateHeight * displayScale)
        let croppedImage = NSImage(size: NSSize(width: row.templateWidth * displayScale, height: row.templateHeight * displayScale))
        croppedImage.addRepresentation(cropped)
        let pngData = try #require(ExportService.opaquePNGData(from: croppedImage))
        return try #require(NSBitmapImageRep(data: pngData))
    }

    func averageBrightnessOfVisibleContent(_ bitmap: NSBitmapImageRep) throws -> CGFloat {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var total: CGFloat = 0
        var count: CGFloat = 0

        for y in stride(from: height / 10, to: height * 9 / 10, by: 12) {
            for x in stride(from: width / 10, to: width * 9 / 10, by: 12) {
                let color = try pixelColor(bitmap, at: (x, y))
                guard color.r < 0.97 || color.g < 0.97 || color.b < 0.97 else { continue }
                total += (color.r + color.g + color.b) / 3
                count += 1
            }
        }

        return try #require(count > 0 ? total / count : nil, "No visible content pixels sampled")
    }

    struct PixelRGB {
        let r: CGFloat, g: CGFloat, b: CGFloat

        func dominates(_ channel: Channel, by margin: CGFloat) -> Bool {
            switch channel {
            case .r: return r > g + margin && r > b + margin
            case .g: return g > r + margin && g > b + margin
            case .b: return b > r + margin && b > g + margin
            }
        }
    }

    enum Channel { case r, g, b }

    func pixelColor(_ bitmap: NSBitmapImageRep, at point: (Int, Int)) throws -> PixelRGB {
        let color = try #require(bitmap.colorAt(x: point.0, y: point.1), "No color at (\(point.0),\(point.1))")
        let srgb = try #require(color.usingColorSpace(.sRGB), "Cannot convert to sRGB")
        return PixelRGB(r: srgb.redComponent, g: srgb.greenComponent, b: srgb.blueComponent)
    }

    /// Asserts that the given channel is the dominant one at a pixel, tolerant of color-space shifts.
    func expectDominant(
        _ bitmap: NSBitmapImageRep,
        at point: (Int, Int),
        channel: Channel,
        margin: CGFloat = 0.15,
        label: String
    ) throws {
        let c = try pixelColor(bitmap, at: point)
        #expect(c.dominates(channel, by: margin),
                "\(label): \(channel) should dominate, got rgb=(\(c.r),\(c.g),\(c.b))")
    }

    /// Scans a grid of pixels and asserts at least one is non-white (i.e. visible content was rendered).
    func expectHasNonWhitePixel(_ bitmap: NSBitmapImageRep, label: String) throws {
        let w = bitmap.pixelsWide, h = bitmap.pixelsHigh
        for y in stride(from: h / 8, to: h * 7 / 8, by: 20) {
            for x in stride(from: w / 8, to: w * 7 / 8, by: 20) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.r < 0.95 || c.g < 0.95 || c.b < 0.95 { return }
            }
        }
        Issue.record("\(label): all sampled pixels were white")
    }

    func expectHasNonWhitePixel(_ bitmap: NSBitmapImageRep, region: CGRect, label: String) throws {
        let minX = max(0, Int(region.minX.rounded(.down)))
        let maxX = min(bitmap.pixelsWide - 1, Int(region.maxX.rounded(.up)))
        let minY = max(0, Int(region.minY.rounded(.down)))
        let maxY = min(bitmap.pixelsHigh - 1, Int(region.maxY.rounded(.up)))
        guard minX <= maxX, minY <= maxY else {
            Issue.record("\(label): sampled region was empty")
            return
        }

        for y in stride(from: minY, through: maxY, by: 12) {
            for x in stride(from: minX, through: maxX, by: 12) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.r < 0.95 || c.g < 0.95 || c.b < 0.95 { return }
            }
        }
        Issue.record("\(label): all sampled pixels were white")
    }

    func expectHasDominantPixel(
        _ bitmap: NSBitmapImageRep,
        region: CGRect,
        channel: Channel,
        margin: CGFloat = 0.15,
        label: String
    ) throws {
        let minX = max(0, Int(region.minX.rounded(.down)))
        let maxX = min(bitmap.pixelsWide - 1, Int(region.maxX.rounded(.up)))
        let minY = max(0, Int(region.minY.rounded(.down)))
        let maxY = min(bitmap.pixelsHigh - 1, Int(region.maxY.rounded(.up)))
        guard minX <= maxX, minY <= maxY else {
            Issue.record("\(label): sampled region was empty")
            return
        }

        for y in stride(from: minY, through: maxY, by: 8) {
            for x in stride(from: minX, through: maxX, by: 8) {
                let c = try pixelColor(bitmap, at: (x, y))
                if c.dominates(channel, by: margin) { return }
            }
        }
        Issue.record("\(label): no sampled pixel had the expected dominant channel")
    }

    func expectNearWhite(_ bitmap: NSBitmapImageRep, at point: (Int, Int), label: String) throws {
        let c = try pixelColor(bitmap, at: point)
        #expect(c.r > 0.95 && c.g > 0.95 && c.b > 0.95,
                "\(label): expected near-white background, got rgb=(\(c.r),\(c.g),\(c.b))")
    }

    func expectWhitePixel(_ bitmap: NSBitmapImageRep, at point: (Int, Int), label: String) throws {
        try expectNearWhite(bitmap, at: point, label: label)
    }

    func expectBitmapsDiffer(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep,
        label: String,
        threshold: CGFloat = 0.12
    ) throws {
        let width = min(lhs.pixelsWide, rhs.pixelsWide)
        let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
        for y in stride(from: height / 8, to: height * 7 / 8, by: 18) {
            for x in stride(from: width / 8, to: width * 7 / 8, by: 18) {
                let left = try pixelColor(lhs, at: (x, y))
                let right = try pixelColor(rhs, at: (x, y))
                let delta = abs(left.r - right.r) + abs(left.g - right.g) + abs(left.b - right.b)
                if delta > threshold {
                    return
                }
            }
        }
        Issue.record("\(label): sampled pixels were effectively identical")
    }

    func cropBitmap(_ image: NSImage, x: CGFloat, width: CGFloat, height: CGFloat) throws -> NSBitmapImageRep {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let cropRect = CGRect(
            x: max(0, floor(x)),
            y: 0,
            width: min(CGFloat(cgImage.width) - max(0, floor(x)), ceil(width)),
            height: min(CGFloat(cgImage.height), ceil(height))
        ).integral
        let cropped = try #require(cgImage.cropping(to: cropRect))
        return NSBitmapImageRep(cgImage: cropped)
    }

    func expectPixelsClose(
        _ lhs: NSBitmapImageRep,
        _ rhs: NSBitmapImageRep,
        at point: (Int, Int),
        tolerance: CGFloat = 0.06,
        label: String
    ) throws {
        let left = try pixelColor(lhs, at: point)
        let right = try pixelColor(rhs, at: point)
        let delta = abs(left.r - right.r) + abs(left.g - right.g) + abs(left.b - right.b)
        #expect(delta < tolerance, "\(label): export/editor delta too large, delta=\(delta)")
    }
}
