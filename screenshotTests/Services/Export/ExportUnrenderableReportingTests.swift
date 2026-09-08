import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// A render source that answers with exactly what it is told to, so a test can hand the export
/// path a resource that is absent, or present and undrawable.
@MainActor
private final class ScriptedRenderSource: RowRenderSource {
    var localeState: LocaleState = .default
    var availableFontFamilySet: Set<String> = []
    /// Referenced by the model, per row, regardless of what `images` can supply.
    var referenced: Set<String> = []
    var images: [String: NSImage] = [:]

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> { referenced }

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] {
        images.filter { fileNames.contains($0.key) }
    }
}

@MainActor
struct ExportUnrenderableReportingTests {

    private func deviceRow(screenshot fileName: String) -> ScreenshotRow {
        var row = ScreenshotRow(templates: [ScreenshotTemplate()], templateWidth: 400, templateHeight: 800, bgColor: .white)
        row.shapes = [CanvasShapeModel(
            type: .device, x: 100, y: 140, width: 200, height: 520,
            color: .clear, deviceCategory: .iphone,
            deviceFrameId: "iphone17-black-portrait",
            screenshotFileName: fileName
        )]
        return row
    }

    private func export(_ source: ScriptedRenderSource, row: ScreenshotRow) async throws -> [String] {
        let dir = makeTemporaryDataDirectory(label: "unrenderable-report")
        defer { try? FileManager.default.removeItem(at: dir) }
        return try await ExportService.exportAll(
            rows: [row], projectName: "Report", to: dir, source: source
        ).unrenderable
    }

    /// The gap this closes: `exportAll` built its contexts by hand instead of through
    /// `RowRenderContext.load`, so it was the one render path that could not name a resource it
    /// had failed to draw — every export reported a clean success over the holes it had written.
    @Test func exportReportsAResourceItCouldNotLoad() async throws {
        let source = ScriptedRenderSource()
        source.referenced = ["ghost.png"]           // referenced by the model, absent from disk
        #expect(try await export(source, row: deviceRow(screenshot: "ghost.png")) == ["ghost.png"])
    }

    /// The shape of failure a presence check cannot see: the loader hands back an `NSImage` for
    /// the file, so it is neither absent nor nil, and it still draws nothing.
    @Test func exportReportsAResourceThatLoadedButCannotDraw() async throws {
        let source = ScriptedRenderSource()
        source.referenced = ["broken.png"]
        source.images = ["broken.png": NSImage(size: NSSize(width: 120, height: 240))]  // no representation
        #expect(try await export(source, row: deviceRow(screenshot: "broken.png")) == ["broken.png"])
    }

    /// Non-vacuity: a resource that loads and draws is not reported, so the two cases above are
    /// about the failure and not about the fixture.
    @Test func exportReportsNothingWhenEveryResourceDraws() async throws {
        let source = ScriptedRenderSource()
        source.referenced = ["good.png"]
        source.images = ["good.png": makeTestImage(width: 120, height: 240)]
        #expect(try await export(source, row: deviceRow(screenshot: "good.png")).isEmpty)
    }

    /// `canDraw` is what separates the two, so pin it directly rather than only through the export.
    @Test func canDrawSeparatesADrawableImageFromAnEmptyOne() {
        #expect(makeTestImage(width: 8, height: 8).canDraw)
        #expect(!NSImage(size: NSSize(width: 8, height: 8)).canDraw, "no representation cannot draw")
        #expect(!NSImage(size: .zero).canDraw, "zero-sized cannot draw")
    }

    /// And the context has to fold both kinds into the set the upload paths refuse on, or widening
    /// the guard to `unrenderableImageFileNames` would silently drop the missing ones.
    @Test func contextFoldsMissingAndUnusableIntoOneReport() {
        let source = ScriptedRenderSource()
        source.referenced = ["ghost.png", "broken.png"]
        source.images = ["broken.png": NSImage(size: NSSize(width: 4, height: 4))]
        var cache: [String: NSImage] = [:]
        let context = RowRenderContext.load(
            row: deviceRow(screenshot: "ghost.png"),
            localeCode: "en", from: source, label: "test", cache: &cache
        )
        #expect(context.missingImageFileNames == ["ghost.png"])
        #expect(context.unusableImageFileNames == ["broken.png"])
        #expect(context.unrenderableImageFileNames == ["broken.png", "ghost.png"])
    }

    /// A seed image replaces a disk resource, so it must be judged on the merged dictionary. Judged
    /// before the merge, an undrawable file that a seed supersedes was still reported — and the
    /// upload services now *throw* on that, so it would abort an upload over something that
    /// renders correctly.
    @Test func aSeedThatReplacesAnUndrawableFileIsNotReported() {
        let source = ScriptedRenderSource()
        source.referenced = ["cover.png"]
        source.images = ["cover.png": NSImage(size: NSSize(width: 4, height: 4))]   // undrawable on disk
        var cache: [String: NSImage] = [:]
        let context = RowRenderContext.load(
            row: deviceRow(screenshot: "cover.png"),
            localeCode: "en", from: source, label: "test", cache: &cache,
            seedImages: ["cover.png": makeTestImage(width: 40, height: 80)]
        )
        #expect(context.unrenderableImageFileNames.isEmpty,
                "the seed supersedes the file, so nothing is unrenderable")
    }

    /// The row-level export path (row export, showcase, iPad share sheet) reports too — it built
    /// its context through `load` and dropped both lists on the floor.
    @Test func rowExportReportsAResourceItCouldNotDraw() async throws {
        let source = ScriptedRenderSource()
        source.referenced = ["ghost.png"]
        let dir = makeTemporaryDataDirectory(label: "row-export-report")
        defer { try? FileManager.default.removeItem(at: dir) }
        var cache: [String: NSImage] = [:]
        let rendered = try await ExportCoordinator.renderRows(
            [deviceRow(screenshot: "ghost.png")],
            into: dir,
            source: source,
            imageCache: &cache,
            render: { $0.templateImage(at: 0) }
        )
        #expect(rendered.fileURLs.count == 1)
        #expect(rendered.unrenderable == ["ghost.png"])
    }
}
