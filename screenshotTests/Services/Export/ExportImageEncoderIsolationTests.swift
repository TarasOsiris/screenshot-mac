import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// The upload paths render on the main actor and hand the CPU-bound follow-up work (PNG encode,
/// checksum) to `@concurrent` helpers. That handoff only actually leaves the main actor because of
/// the `@concurrent`: this target builds with `NonisolatedNonsendingByDefault`, under which a plain
/// `nonisolated async` inherits the caller's actor, runs on the main thread, and — having no
/// suspension point — never even yields the main queue, so a whole render loop becomes one
/// uninterrupted main-actor job. That shipped in 4.0 (108) as a multi-second app hang.
@MainActor
struct ExportImageEncoderIsolationTests {

    @MainActor private final class Flag {
        var didRun = false
    }

    /// Fails if `work` runs inline on the main actor: queued main-actor work (progress updates,
    /// window dragging) only gets a slot if awaiting `work` actually suspends.
    private func expectSuspendsMainActor(
        _ work: () async throws -> Void,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async rethrows {
        let flag = Flag()
        Task { @MainActor in flag.didRun = true }
        #expect(flag.didRun == false, sourceLocation: sourceLocation)
        try await work()
        #expect(flag.didRun, sourceLocation: sourceLocation)
    }

    @Test func opaquePNGEncodeSuspendsTheMainActor() async throws {
        let image = makeTestImage(width: 120, height: 80)
        await expectSuspendsMainActor {
            _ = await ExportImageEncoder.opaquePNGDataOffMain(from: image)
        }
    }

    @Test func fileChecksumSuspendsTheMainActor() async throws {
        let image = makeTestImage(width: 120, height: 80)
        let data = try #require(ExportService.opaquePNGData(from: image))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolation-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try await expectSuspendsMainActor {
            _ = try await AppStoreConnectScreenshotSyncService.fileChecksum(at: url)
        }
    }

    @Test func offMainEncodeMatchesSynchronousEncode() async throws {
        let image = makeTestImage(width: 120, height: 80)
        let sync = try #require(ExportService.opaquePNGData(from: image))
        let offMain = try #require(await ExportImageEncoder.opaquePNGDataOffMain(from: image))
        #expect(sync == offMain)
    }

    /// `renderSingleTemplateImage` has to run on the main actor and `taskGroup.addTask` doesn't
    /// suspend, so without an explicit yield a whole locale group's templates render as one
    /// uninterrupted main-actor job — the shape that shipped as an app hang in 4.0 (108).
    ///
    /// Asserting "it suspends" wouldn't catch that: the task-group drain at the end of the group
    /// suspends either way. Cancellation ordering separates them. Main-actor jobs run FIFO, so the
    /// `Task.yield()` below hands off to `exportTask`, which runs until *its* first suspension and
    /// re-enqueues behind this test. Cancelling there lands before the next template's
    /// `Task.checkCancellation()` only if the render loop yields per template; otherwise the whole
    /// group has already rendered and the export runs to completion.
    @Test func exportAllYieldsBetweenTemplatesSoCancellationLandsMidRow() async throws {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 200,
            templateHeight: 400,
            bgColor: .white
        )
        row.label = "Yielding"

        let tempDir = makeTemporaryDataDirectory(label: "export-isolation-tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let exportTask = Task { @MainActor in
            try await ExportService.exportAll(
                rows: [row],
                projectName: "YieldProject",
                to: tempDir,
                imageProvider: { _, _ in [:] },
                localeState: .default
            )
        }

        await Task.yield()
        exportTask.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await exportTask.value
        }
    }
}
