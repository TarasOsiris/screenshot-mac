import AppKit
import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
struct BundledTemplateRenderTests {

    private static let previewMaxDimension: CGFloat = 1200

    private static func bundledTemplateIDs() throws -> [String] {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        return try FileManager.default.contentsOfDirectory(atPath: bundleURL.path)
            .filter { FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent($0).appendingPathComponent("project.json").path) }
            .sorted()
    }

    private static func bundledTemplate(_ id: String) throws -> ProjectData {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        let data = try Data(contentsOf: bundleURL.appendingPathComponent(id).appendingPathComponent("project.json"))
        return try PersistenceService.decoder.decode(ProjectData.self, from: data)
    }

    private static func renderColumn(_ index: Int, of row: ScreenshotRow, in project: ProjectData) -> NSImage {
        RowRenderer.renderSingleTemplateImage(
            index: index,
            row: row,
            localeState: project.localeState ?? .default,
            displayScale: min(1, previewMaxDimension / max(row.templateWidth, row.templateHeight))
        )
    }

    // SCREENSHOT-BRO-1Y: a 45°-rotated device at this scale aborted in `_nsis_frameInEngine`.
    @Test func amethystIPadFirstColumnRenders() throws {
        let project = try Self.bundledTemplate("amethyst")
        let row = try #require(project.rows.first { $0.defaultDeviceCategory == .ipadPro11 })
        #expect(Self.renderColumn(0, of: row, in: project).size.width > 0)
    }

    /// The abort came from the image drop target every image-bearing shape carries, not from the
    /// device frame — an image shape at the same rotation and size hit it too.
    @Test func rotatedImageShapeRenders() throws {
        let project = try Self.bundledTemplate("amethyst")
        var row = try #require(project.rows.first { $0.defaultDeviceCategory == .ipadPro11 })
        let device = try #require(row.shapes.first { $0.type == .device })
        var image = try #require(row.shapes.first { $0.type == .image })
        image.x = device.x
        image.y = device.y
        image.width = device.width
        image.height = device.height
        image.rotation = 45
        row.shapes = [image]
        #expect(Self.renderColumn(0, of: row, in: project).size.width > 0)
    }

    /// Every column of every starter template, at the scale MCP `render_preview` uses. A crash
    /// here takes the whole test process down, which is the point: it is what the user's app does.
    @Test func everyBundledTemplateColumnRenders() throws {
        var rendered = 0
        for id in try Self.bundledTemplateIDs() {
            let project = try Self.bundledTemplate(id)
            for row in project.rows {
                for index in row.templates.indices {
                    let image = Self.renderColumn(index, of: row, in: project)
                    #expect(image.size.width > 0, "\(id) row '\(row.label)' column \(index) rendered empty")
                    rendered += 1
                }
            }
        }
        #expect(rendered > 100)
    }
}
