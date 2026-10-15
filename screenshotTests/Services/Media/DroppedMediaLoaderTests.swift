import AppKit
import Foundation
@testable import Screenshot_Bro
import Testing

struct DroppedMediaLoaderTests {

    private func write(_ data: Data, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url
    }

    private let svg = #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 40 20"><rect width="40" height="20" fill="red"/></svg>"#

    @Test func anSvgFileDecodesAsMarkup() throws {
        let url = try write(Data(svg.utf8), named: "shape.svg")
        defer { try? FileManager.default.removeItem(at: url) }

        guard case .svg(let content) = DroppedMediaLoader.media(at: url, confirmingImageType: true) else {
            Issue.record("expected SVG markup")
            return
        }
        #expect(content.contains("<rect"))
    }

    @Test func aRenderableSvgReportsItsViewBoxSize() throws {
        let url = try write(Data(svg.utf8), named: "shape.svg")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(try DroppedMediaLoader.renderableSvg(at: url).naturalSize == CGSize(width: 40, height: 20))
    }

    /// A generic file URL promises nothing, so a non-image file is refused rather than decoded.
    @Test func aConfirmedFileMustBeAnImage() throws {
        let url = try write(Data("not an image".utf8), named: "notes.txt")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DroppedMediaLoader.image(at: url, confirmingImageType: true) == nil)
        #expect(DroppedMediaLoader.media(at: url, confirmingImageType: true) == nil)
    }

    @Test func aPNGDecodesAsAnImage() throws {
        let png = try #require(ExportService.opaquePNGData(from: makeTestImage(width: 8, height: 4)))
        let url = try write(png, named: "shot.png")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(DroppedMediaLoader.image(at: url, confirmingImageType: true)?.size == CGSize(width: 8, height: 4))
    }
}
