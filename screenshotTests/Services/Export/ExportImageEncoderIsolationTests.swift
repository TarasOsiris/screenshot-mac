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

    @Test func opaquePNGEncodeSuspendsTheMainActor() async throws {
        let image = makeTestImage(width: 120, height: 80)
        await expectSuspendsMainActor {
            _ = await ExportImageEncoder.opaquePNGDataOffMain(from: image)
        }
    }

    @Test func alphaPreservingPNGEncodeSuspendsTheMainActor() async throws {
        let image = makeTestImage(width: 120, height: 80)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        await expectSuspendsMainActor {
            _ = await ExportImageEncoder.pngDataOffMain(fromCGImage: cgImage)
        }
    }

    @Test func downsampleSuspendsTheMainActor() async throws {
        let image = makeTestImage(width: 2400, height: 1600)
        let data = try #require(ExportService.pngData(from: image))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("downsample-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await expectSuspendsMainActor {
            _ = await ImageDownsampler.downsampledCGImageOffMain(
                at: url,
                maxDimension: ImageDownsampler.editorImageMaxDimension
            )
        }
    }

    /// The screenshot-import path swapped `ExportService.pngData` for the `@concurrent` sibling;
    /// the persisted resource bytes must not change with it.
    @Test func alphaPreservingOffMainEncodeMatchesSynchronousEncode() async throws {
        let image = makeTestImage(width: 120, height: 80)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let sync = try #require(ExportService.pngData(from: image))
        let offMain = try #require(await ExportImageEncoder.pngDataOffMain(fromCGImage: cgImage))
        #expect(sync == offMain)
    }

    /// The atomic write, not just the encode, has to leave the main actor: on an iCloud-backed
    /// resources folder it is the slowest step of a screenshot import (SCREENSHOT-BRO-W).
    @Test(arguments: [false, true]) func stagedImageWriteSuspendsTheMainActor(copyingSource: Bool) async throws {
        let image = makeTestImage(width: 400, height: 300)
        let dir = FileManager.default.temporaryDirectory
        let destination = dir.appendingPathComponent("staged-dst-\(UUID().uuidString).png")
        let source = dir.appendingPathComponent("staged-src-\(UUID().uuidString).png")
        let sourceData = try #require(ExportService.pngData(from: image))
        try sourceData.write(to: source)
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: destination)
        }

        try await expectSuspendsMainActor {
            if copyingSource {
                try await StagedImageWriter.persist(copying: source, to: destination)
            } else {
                let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                try await StagedImageWriter.persist(encoding: cgImage, to: destination)
            }
        }
        // An already-PNG source is copied verbatim; anything else is transcoded.
        #expect(try Data(contentsOf: destination) == sourceData)
    }

    /// The staged path reports a failing write as `writeFailed` carrying the reason, so the user
    /// sees the real cause rather than a generic `Error.localizedDescription`.
    @Test func stagedImageWriteSurfacesTheWriteFailureReason() async throws {
        struct DiskFull: LocalizedError { var errorDescription: String? { "Disk full" } }
        let image = makeTestImage(width: 40, height: 30)
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("staged-fail-\(UUID().uuidString).png")

        await #expect(throws: StagedImageWriteError.self) {
            try await StagedImageWriter.persist(
                encoding: cgImage,
                to: destination,
                write: { _, _ in throw DiskFull() }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
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

    @Test func svgRenderOffMainSuspendsTheMainActorAndFillsTheCache() async throws {
        // Unique content so a raster-cache hit from another test can't satisfy the check.
        let svg = "<svg xmlns='http://www.w3.org/2000/svg' width='10' height='10'>"
            + "<rect width='10' height='10' fill='#AB12CD'/><!-- isolation --></svg>"
        let targetSize = CGSize(width: 64, height: 64)
        await expectSuspendsMainActor {
            await SvgHelper.renderImageOffMain(from: svg, useColor: false, color: .white, targetSize: targetSize)
        }
        #expect(SvgHelper.cachedRender(from: svg, useColor: false, color: .white, targetSize: targetSize) != nil)
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

    /// The editor's device snapshots used to run inside a `.task` on a MainActor-isolated `async
    /// func`, so the whole synchronous SceneKit pass executed as one uninterrupted main-actor job.
    /// `DeviceModelSnapshotQueue` is an `actor`, not a `@concurrent` function — an actor's own
    /// methods always hop to its executor, so this is what proves the hop actually happens.
    @Test func deviceModelSnapshotSuspendsTheMainActor() async throws {
        let frame = try #require(DeviceFrameCatalog.frame(for: "iphone17promaxmodel-default-portrait"))
        let request = DeviceModelSnapshotRequest.make(
            frame: frame,
            width: 330,
            height: 717,
            isExport: false,
            screenshotImage: nil,
            pitch: 0,
            yaw: 0,
            bodyMaterial: DeviceBodyMaterial(),
            lighting: DeviceLighting(),
            bodyColor: .black
        )
        await expectSuspendsMainActor {
            _ = await DeviceModelSnapshotQueue.shared.snapshot(request)
        }
    }
}
