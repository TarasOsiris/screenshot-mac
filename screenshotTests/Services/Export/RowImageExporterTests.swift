import AppKit
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct RowImageExporterTests {

    @Test func writesOneDecodablePNGPerTemplateInOrder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("RowImageExporter-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let context = RowRenderContext(
            row: makeTestRow(width: 120, height: 240, templateCount: 3),
            images: [:],
            localeCode: nil,
            availableFontFamilies: [],
            label: "exporter test"
        )

        let urls = try await RowImageExporter.writePNGs(context, to: folder) { "shot-\($0).png" }

        #expect(urls.map(\.lastPathComponent) == ["shot-0.png", "shot-1.png", "shot-2.png"])
        for url in urls {
            let image = try #require(NSBitmapImageRep(data: try Data(contentsOf: url)))
            #expect(image.pixelsWide == 120 && image.pixelsHigh == 240)
        }
    }
}
