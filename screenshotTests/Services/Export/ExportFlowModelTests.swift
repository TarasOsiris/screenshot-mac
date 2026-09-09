import Foundation
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// A fixture document. The point of `ExportDocument` is that these tests need no `AppState`.
@MainActor
private final class StubDocument: ExportDocument {
    var rows: [ScreenshotRow]
    var activeProjectName: String
    var localeState: LocaleState = .default
    var availableFontFamilySet: Set<String> = []
    /// Counted rather than ignored: every export entry point must land an in-flight continuous
    /// edit before it reads `rows`, or it renders the value from before the drag.
    private(set) var commitPendingEditsCount = 0

    init(rows: [ScreenshotRow], projectName: String = "Fixture") {
        self.rows = rows
        self.activeProjectName = projectName
    }

    func commitPendingEdits() { commitPendingEditsCount += 1 }

    /// Names the renderer will ask for and never receive — the shape of a project whose resource
    /// files are gone, which is what makes an export write blank device frames.
    var unreadableResourceNames: Set<String> = []

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        unreadableResourceNames
    }

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] { [:] }
}

@MainActor
struct ExportFlowModelTests {

    private func makeDefaults(_ label: String) -> UserDefaults {
        let suite = "ExportFlowModelTests.\(label).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeRow(_ label: String) -> ScreenshotRow {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: 80,
            templateHeight: 120,
            bgColor: .white
        )
        row.label = label
        row.shapes = []
        return row
    }

    private func waitForIdle(_ model: ExportFlowModel) async throws {
        for _ in 0..<400 where model.isExporting {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(!model.isExporting, "export did not finish")
    }

    @Test func rowExportWritesOneZeroPaddedFilePerRow() async throws {
        let model = ExportFlowModel(defaults: makeDefaults("rows"))
        let document = StubDocument(rows: [makeRow("Alpha"), makeRow("Beta")])
        let base = makeTemporaryDataDirectory(label: "export-flow-rows")
        defer { try? FileManager.default.removeItem(at: base) }

        model.exportRows(
            document: document,
            into: base,
            folderName: "rows",
            delivery: .revealInPlace
        ) { context in context.rowImage() }

        try await waitForIdle(model)

        #expect(model.errorMessage == nil)
        #expect(model.total == 2)
        #expect(document.commitPendingEditsCount == 1, "Export must land an in-flight edit before reading rows")
        let destDir = try #require(
            try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil).first
        )
        let files = try FileManager.default.contentsOfDirectory(at: destDir, includingPropertiesForKeys: nil)
            .map(\.lastPathComponent)
            .sorted()
        #expect(files == ["01_Alpha.png", "02_Beta.png"])
    }

    /// The temp-folder cleanup used to be `try? FileManager.default.removeItem(...)` repeated at
    /// six call sites in the view; a staged export that fails must not leave the folder behind.
    @Test func failedStagedExportRemovesTheTempFolder() async throws {
        let model = ExportFlowModel(defaults: makeDefaults("cleanup"))
        let document = StubDocument(rows: [makeRow("Alpha")])
        let base = makeTemporaryDataDirectory(label: "export-flow-cleanup")
        // Removing the base folder makes `createDirectory` inside it fail, standing in for any
        // mid-render failure.
        try FileManager.default.removeItem(at: base)
        try Data().write(to: base)
        defer { try? FileManager.default.removeItem(at: base) }

        model.exportRows(
            document: document,
            into: base,
            folderName: "rows",
            delivery: .stageDestination
        ) { context in context.rowImage() }

        try await waitForIdle(model)

        #expect(model.errorMessage != nil, "the failure must surface")
        #expect(model.pendingExport == nil)
        #expect(!FileManager.default.fileExists(atPath: base.path), "temp folder must be cleaned up")
    }

    @Test func emptyRowSetIsANoOp() async throws {
        let model = ExportFlowModel(defaults: makeDefaults("empty"))
        let document = StubDocument(rows: [])
        let base = makeTemporaryDataDirectory(label: "export-flow-empty")
        defer { try? FileManager.default.removeItem(at: base) }

        model.exportRows(document: document, into: base, folderName: "rows", delivery: .revealInPlace) {
            context in context.rowImage()
        }

        #expect(!model.isExporting)
        #expect(model.total == 0)
    }

    @Test func discardingAStagedExportRemovesTheFilesAndClearsIt() throws {
        let model = ExportFlowModel(defaults: makeDefaults("discard"))
        let base = makeTemporaryDataDirectory(label: "export-flow-discard")
        let file = base.appendingPathComponent("01.png")
        try Data([0x1]).write(to: file)

        model.pendingExport = PendingExport(fileURLs: [file], folderURL: base, cleanupBaseURL: base)
        model.discardPendingExport()

        #expect(model.pendingExport == nil)
        #expect(!FileManager.default.fileExists(atPath: base.path))
    }

    /// Success is transient by design — the toolbar button reverts from "Exported" after a beat.
    @Test func showingSuccessSetsTheTransientFlag() {
        let model = ExportFlowModel(defaults: makeDefaults("success"))
        #expect(!model.exportSuccess)
        model.showSuccess(projectName: "Fixture", destination: "folder")
        #expect(model.exportSuccess)
        #expect(model.incompleteMessage == nil)
    }

    /// The report used to be recorded and then dropped: a user whose screenshots had gone missing
    /// got "12 screenshots exported" over a folder of blank frames and uploaded them.
    @Test func anExportThatDrewHolesSaysSoInsteadOfClaimingSuccess() async throws {
        let model = ExportFlowModel(defaults: makeDefaults("holes"))
        let document = StubDocument(rows: [makeRow("Alpha")])
        document.unreadableResourceNames = ["gone.png"]
        let base = makeTemporaryDataDirectory(label: "export-flow-holes")
        defer { try? FileManager.default.removeItem(at: base) }

        model.exportRows(
            document: document,
            into: base,
            folderName: "holes",
            delivery: .revealInPlace
        ) { context in context.rowImage() }

        try await waitForIdle(model)

        #expect(model.errorMessage == nil)
        #expect(model.unrenderableFileNames == ["gone.png"])
        #expect(model.incompleteMessage != nil, "A run that drew holes must say so before the files are uploaded")
    }

    /// The alert is bound to `incompleteMessage` and only the OK button clears it, so a run that
    /// started with it on screen used to leave it there describing files nobody exported.
    @Test func aNewRunClearsThePreviousRunsBlankFrameReport() async throws {
        let model = ExportFlowModel(defaults: makeDefaults("holes-cleared"))
        let document = StubDocument(rows: [makeRow("Alpha")])
        document.unreadableResourceNames = ["gone.png"]
        let base = makeTemporaryDataDirectory(label: "export-flow-holes-cleared")
        defer { try? FileManager.default.removeItem(at: base) }

        model.exportRows(
            document: document,
            into: base,
            folderName: "first",
            delivery: .revealInPlace
        ) { context in context.rowImage() }
        try await waitForIdle(model)
        #expect(model.incompleteMessage != nil)

        document.unreadableResourceNames = []
        model.exportRows(
            document: document,
            into: base,
            folderName: "second",
            delivery: .revealInPlace
        ) { context in context.rowImage() }
        try await waitForIdle(model)

        #expect(model.incompleteMessage == nil, "the previous run's alert must not survive a clean one")
        #expect(model.unrenderableFileNames.isEmpty)
    }
}
