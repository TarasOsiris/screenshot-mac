import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// The PNG passthrough writes an already-PNG source's bytes verbatim instead of decoding and
/// re-deflating through `NSBitmapImageRep`, which normalized bit depth and color space. That is a
/// change to what lands in `resources/`, and exports composite those files at full resolution — so
/// what has to hold is that the *exported* image is unchanged, not merely that the resource decodes.
///
/// Deliberately hermetic: no `AppState`, so it never touches the process-global
/// `SCREENSHOT_DATA_DIR` and cannot race the suites that do (see the note on `makeEmptyTestState`).
@MainActor
struct StagedImageWriteExportParityTests {

    /// Persists `source` the two ways the import can, then renders each through the export path.
    private func exportedBytes(persisting source: URL, viaPassthrough: Bool) async throws -> Data {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("parity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let destination = dir.appendingPathComponent("shot.png")
        if viaPassthrough {
            try await StagedImageWriter.persist(copying: source, to: destination)
        } else {
            let image = try #require(NSImage(contentsOf: source))
            let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            try await StagedImageWriter.persist(encoding: cgImage, to: destination)
        }

        let loaded = try #require(NSImage(contentsOf: destination), "resource should load back off disk")
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 500, templateHeight: 1000, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device, x: 150, y: 220, width: 200, height: 520,
            color: .clear, deviceCategory: .iphone,
            deviceFrameId: "iphone17-black-portrait",
            screenshotFileName: "shot.png"
        )]

        let rendered = RowRenderer.renderSingleTemplateImage(
            index: 0, row: row, screenshotImages: ["shot.png": loaded]
        )
        let bytes = try #require(ExportService.opaquePNGData(from: rendered))

        // Non-vacuity: the same row without the resource renders differently, so a byte match
        // between the two routes is a match on output that actually contains the screenshot.
        let blank = RowRenderer.renderSingleTemplateImage(index: 0, row: row, screenshotImages: [:])
        #expect(try bytes != #require(ExportService.opaquePNGData(from: blank)),
                "the screenshot should be visible in the export")
        return bytes
    }

    /// Same pixels in, same exported bytes out, whichever way the resource was persisted.
    @Test(arguments: ["8-bit RGBA", "16-bit", "grayscale", "display-p3"])
    func passthroughAndTranscodeExportIdentically(variant: String) async throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("parity-src-\(UUID().uuidString).png")
        try #require(pngData(for: variant)).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let viaPassthrough = try await exportedBytes(persisting: source, viaPassthrough: true)
        let viaTranscode = try await exportedBytes(persisting: source, viaPassthrough: false)

        #expect(viaPassthrough == viaTranscode,
                "\(variant): passthrough export differs from the re-encoded export")
    }

    /// Builds a PNG in the named representation, so each case exercises something the old
    /// re-encode would have normalized away.
    private func pngData(for variant: String) -> Data? {
        let image = makeTestImage(width: 1206, height: 2622)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let converted: NSBitmapImageRep?
        switch variant {
        case "16-bit": converted = rep.converting(to: .genericRGB, renderingIntent: .default)
        case "grayscale": converted = rep.converting(to: .genericGray, renderingIntent: .default)
        case "display-p3": converted = rep.converting(to: .displayP3, renderingIntent: .default)
        default: converted = rep
        }
        return (converted ?? rep).representation(using: .png, properties: [:])
    }
}
