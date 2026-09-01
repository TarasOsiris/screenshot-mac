import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Regression cover for the 3D (USDZ) device frames. A cold SceneKit renderer used to hand back a
/// fully transparent snapshot, which shipped App Store screenshots with the device missing.
@MainActor
struct DeviceModelSnapshotTests {

    private static let modelFrameId = "iphone17promaxmodel-default-portrait"

    private func modelFrame() throws -> DeviceFrame {
        let frame = try #require(DeviceFrameCatalog.frame(for: Self.modelFrameId))
        #expect(frame.isModelBacked, "Test needs a USDZ-backed frame")
        return frame
    }

    // MARK: - Cold render

    @Test func coldSnapshotRendersVisiblePixels() throws {
        let frame = try modelFrame()
        let image = try #require(
            DeviceModelRenderer.snapshotDeviceModel(request(frame: frame)),
            "Device model snapshot returned nil"
        )
        #expect(maxAlpha(of: image) > 0, "Snapshot was fully transparent — the device did not render")
    }

    @Test func rotatedSnapshotRendersVisiblePixels() throws {
        let frame = try modelFrame()
        let image = try #require(
            DeviceModelRenderer.snapshotDeviceModel(request(frame: frame, pitch: 12, yaw: -18))
        )
        #expect(maxAlpha(of: image) > 0)
    }

    // MARK: - Export path

    @Test func exportRendersDeviceForModelBackedFrame() throws {
        let frame = try modelFrame()
        let fileName = "shot.png"
        let images = [fileName: makeTestImage(width: 1320, height: 2868)]

        var device = CanvasShapeModel(
            type: .device,
            x: 160,
            y: 300,
            width: 1000,
            height: 2172,
            deviceCategory: .iphone
        )
        device.deviceFrameId = frame.id
        device.displayImageFileName = fileName

        var row = ScreenshotRow(
            templates: [ScreenshotTemplate()],
            templateWidth: 1320,
            templateHeight: 2868,
            bgColor: .white,
            backgroundStyle: .color
        )
        row.shapes = [device]

        var emptyRow = row
        emptyRow.shapes = []

        let withDevice = try bitmap(of: RowRenderer.renderSingleTemplateImage(
            index: 0, row: row, screenshotImages: images
        ))
        let withoutDevice = try bitmap(of: RowRenderer.renderSingleTemplateImage(
            index: 0, row: emptyRow, screenshotImages: images
        ))

        #expect(withDevice.pixelsWide == withoutDevice.pixelsWide)
        #expect(
            differingSampleCount(withDevice, withoutDevice) > 0,
            "Export rendered no device — the template is identical to one with no shapes"
        )
    }

    // MARK: - Snapshot cache key

    @Test func snapshotKeyDistinguishesImagesByIdentity() throws {
        let frame = try modelFrame()
        let a = makeTestImage(width: 1320, height: 2868)
        let b = makeTestImage(width: 1320, height: 2868)

        let keyA = key(frame: frame, image: a, identity: "a.png")
        let keyB = key(frame: frame, image: b, identity: "b.png")
        let keyASecondLoad = key(frame: frame, image: b, identity: "a.png")

        #expect(keyA.cacheKey != keyB.cacheKey, "Different images must not share a cache entry")
        #expect(
            keyA.cacheKey == keyASecondLoad.cacheKey,
            "The same file reloaded into a new NSImage must reuse its cache entry"
        )
        #expect(keyA.isCacheable)
    }

    @Test func snapshotKeyIsNotCacheableWithoutIdentity() throws {
        let frame = try modelFrame()
        let withoutIdentity = key(frame: frame, image: makeTestImage(width: 100, height: 200), identity: nil)
        let noImage = key(frame: frame, image: nil, identity: nil)

        #expect(withoutIdentity.isCacheable == false, "An unidentifiable image must re-render, never cache")
        #expect(noImage.isCacheable, "An empty device frame is safely cacheable")
    }

    // MARK: - Pose quantization

    /// A rotation slider sweeps far finer than a pixel of silhouette. Without a rung, every mouse
    /// position was a distinct key: one sweep evicted the whole snapshot cache and nothing ever
    /// hit it on the way back.
    @Test func poseAnglesWithinOneRungShareAKey() throws {
        let frame = try modelFrame()
        let step = DeviceModelRenderer.snapshotAngleStep
        #expect(key(frame: frame, image: nil, identity: nil, pitch: -22) ==
                key(frame: frame, image: nil, identity: nil, pitch: -22 + step / 4))
    }

    @Test func poseAnglesARungApartDoNotShareAKey() throws {
        let frame = try modelFrame()
        let step = DeviceModelRenderer.snapshotAngleStep
        #expect(key(frame: frame, image: nil, identity: nil, pitch: -22) !=
                key(frame: frame, image: nil, identity: nil, pitch: -22 - step))
    }

    /// The rung must stay small enough that a slider still feels continuous.
    @Test func poseRungIsSubDegree() {
        #expect(DeviceModelRenderer.snapshotAngleStep > 0)
        #expect(DeviceModelRenderer.snapshotAngleStep <= 0.5)
    }

    // MARK: - Helpers

    private func key(
        frame: DeviceFrame,
        image: NSImage?,
        identity: String?,
        pixelSize: CGSize = DeviceModelRenderer.snapshotPixelSize(width: 330, height: 717, isExport: false),
        pitch: Double = 0,
        bodyColor: Color = .black
    ) -> DeviceModelRenderer.SnapshotKey {
        DeviceModelRenderer.snapshotKey(
            frame: frame,
            pixelSize: pixelSize,
            screenshotImage: image,
            screenshotImageIdentity: identity,
            pitch: pitch,
            yaw: 0,
            bodyMaterial: DeviceBodyMaterial(),
            lighting: DeviceLighting(),
            bodyColor: bodyColor
        )
    }

    private func request(
        frame: DeviceFrame,
        pitch: Double = 0,
        yaw: Double = 0,
        isExport: Bool = false
    ) -> DeviceModelSnapshotRequest {
        DeviceModelSnapshotRequest.make(
            frame: frame,
            width: 330,
            height: 717,
            isExport: isExport,
            screenshotImage: makeTestImage(width: 1320, height: 2868),
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: DeviceBodyMaterial(),
            lighting: DeviceLighting(),
            bodyColor: .black
        )
    }

    private func maxAlpha(of cgImage: CGImage) -> Int {
        let side = 48
        var alpha = [UInt8](repeating: 0, count: side * side)
        guard let context = CGContext(
            data: &alpha,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return 0 }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return Int(alpha.max() ?? 0)
    }

    private func bitmap(of image: NSImage) throws -> NSBitmapImageRep {
        let data = try #require(ExportService.opaquePNGData(from: image))
        return try #require(NSBitmapImageRep(data: data))
    }

    private func differingSampleCount(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
        let width = min(lhs.pixelsWide, rhs.pixelsWide)
        let height = min(lhs.pixelsHigh, rhs.pixelsHigh)
        var differing = 0
        for y in stride(from: 0, to: height, by: 16) {
            for x in stride(from: 0, to: width, by: 16) {
                guard let left = lhs.colorAt(x: x, y: y), let right = rhs.colorAt(x: x, y: y) else { continue }
                let delta = abs(left.redComponent - right.redComponent)
                    + abs(left.greenComponent - right.greenComponent)
                    + abs(left.blueComponent - right.blueComponent)
                if delta > 0.02 { differing += 1 }
            }
        }
        return differing
    }

    // MARK: - Pixel box

    /// The export budget is what pins exported bytes, so it must be numerically what it always was:
    /// 3× the points, capped so the long edge never exceeds 4096.
    @Test func exportSnapshotPixelSizeIsUnchanged() {
        for (width, height) in [(330.0, 717.0), (1320.0, 2868.0), (2000.0, 400.0), (10.0, 10.0)] {
            let legacyScale = min(3, max(1, 4096 / max(width, height, 1)))
            let expected = CGSize(
                width: max(1, (width * legacyScale).rounded(.up)),
                height: max(1, (height * legacyScale).rounded(.up))
            )
            let actual = DeviceModelRenderer.snapshotPixelSize(width: width, height: height, isExport: true)
            #expect(actual == expected, "Export pixel box moved for \(width)×\(height)")
        }
    }

    /// The pixel box lands in the cache key, so a continuous value would miss on every pinch tick
    /// and pay a full SceneKit render per device per frame.
    @Test func editorSnapshotPixelSizeIsStableAcrossSmallZoomChanges() {
        let baseWidth = 330.0
        let baseHeight = 717.0
        let reference = DeviceModelRenderer.snapshotPixelSize(width: baseWidth, height: baseHeight, isExport: false)
        for zoom in [1.0, 1.02, 1.05, 1.10, 1.25, 2.0] {
            let size = DeviceModelRenderer.snapshotPixelSize(
                width: baseWidth * zoom,
                height: baseHeight * zoom,
                isExport: false
            )
            #expect(size == reference, "Zoom \(zoom) changed the editor pixel box")
        }
    }

    @Test func editorSnapshotIsCappedAndKeepsAspectRatio() {
        for (width, height) in [(330.0, 717.0), (717.0, 330.0), (450.0, 445.0), (120.0, 260.0)] {
            let size = DeviceModelRenderer.snapshotPixelSize(width: width, height: height, isExport: false)
            #expect(max(size.width, size.height) <= DeviceModelRenderer.editorSnapshotMaxEdge)
            let requested = width / height
            let produced = size.width / size.height
            #expect(abs(requested - produced) < 0.02, "Aspect drifted for \(width)×\(height)")
        }
    }

    /// Small devices are already below the cap, so they keep the full supersample.
    @Test func smallDeviceKeepsFullSupersample() {
        let size = DeviceModelRenderer.snapshotPixelSize(width: 120, height: 260, isExport: false)
        #expect(max(size.width, size.height) >= 260 * 3)
    }

    // MARK: - Off-main render

    @Test func offMainSnapshotRendersVisiblePixels() async throws {
        let frame = try modelFrame()
        let image = try #require(await DeviceModelSnapshotQueue.shared.snapshot(request(frame: frame)))
        #expect(maxAlpha(of: image) > 0)
    }

    @Test func offMainAndSynchronousSnapshotsAgreeOnDimensions() async throws {
        let frame = try modelFrame()
        let sync = try #require(DeviceModelRenderer.snapshotDeviceModel(request(frame: frame)))
        let offMain = try #require(await DeviceModelSnapshotQueue.shared.snapshot(request(frame: frame)))
        // Pixels are not compared: GPU rendering is not bit-deterministic across runs.
        #expect(sync.width == offMain.width)
        #expect(sync.height == offMain.height)
        #expect(maxAlpha(of: offMain) > 0)
    }

    /// The stand-in is what keeps a 3D device from flattening to the front-on fallback while its next
    /// raster renders, so it has to survive every input one shape can change.
    @Test func standInSurvivesEveryChangeWithinOneFrame() throws {
        let frame = try modelFrame()
        let image = makeTestImage(width: 100, height: 200)
        let base = key(frame: frame, image: image, identity: "a.png", pixelSize: CGSize(width: 256, height: 512))

        let variants: [(String, DeviceModelRenderer.SnapshotKey)] = [
            ("a zoom step", key(frame: frame, image: image, identity: "a.png", pixelSize: CGSize(width: 512, height: 1024))),
            ("a rotation tick", key(frame: frame, image: image, identity: "a.png", pitch: 30)),
            ("a replaced screenshot", key(frame: frame, image: makeTestImage(width: 300, height: 600), identity: "b.png")),
            ("a cleared screenshot", key(frame: frame, image: nil, identity: nil)),
            ("a new body colour", key(frame: frame, image: image, identity: "a.png", bodyColor: .white))
        ]
        for (change, variant) in variants {
            #expect(base.canStandInFor(variant), "\(change) must not drop back to the fallback")
        }
    }

    /// A different model or orientation is a different silhouette, so the previous raster would be
    /// wrong rather than merely stale.
    @Test func standInIsRefusedAcrossFrames() throws {
        let portrait = try modelFrame()
        let landscape = try #require(DeviceFrameCatalog.frame(for: "iphone17promaxmodel-default-landscape"))
        let otherModel = try #require(DeviceFrameCatalog.frame(for: "iphone16model-default-portrait"))
        let image = makeTestImage(width: 100, height: 200)
        let base = key(frame: portrait, image: image, identity: "a.png")

        #expect(!base.canStandInFor(key(frame: landscape, image: image, identity: "a.png")))
        #expect(!base.canStandInFor(key(frame: otherModel, image: image, identity: "a.png")))
    }

    /// The render debounce gates on this. A zoom sweep re-keys every device in the row at once and is
    /// worth coalescing; a pose tick is one shape's, and holding it back froze the rotation sliders,
    /// which tick faster than the delay.
    @Test func onlyADensityChangeIsCoalesced() throws {
        let frame = try modelFrame()
        let image = makeTestImage(width: 100, height: 200)
        let base = key(frame: frame, image: image, identity: "a.png", pixelSize: CGSize(width: 256, height: 512))
        let zoomed = key(frame: frame, image: image, identity: "a.png", pixelSize: CGSize(width: 512, height: 1024))

        #expect(base != zoomed)
        #expect(base.matchesIgnoringPixelSize(zoomed))
        #expect(!base.matchesIgnoringPixelSize(key(frame: frame, image: image, identity: "a.png", pitch: 30)))
        #expect(!base.matchesIgnoringPixelSize(key(frame: frame, image: image, identity: "b.png")))
    }

    /// The stand-in rule is deliberately far weaker than the cache rule. Substituting it into
    /// `cachedSnapshot` would serve the exporter an editor-density raster.
    @Test func cacheKeySeparatesResolutionsThatShareAStandIn() throws {
        let frame = try modelFrame()
        let image = makeTestImage(width: 100, height: 200)
        let small = key(frame: frame, image: image, identity: "id", pixelSize: CGSize(width: 256, height: 512))
        let large = key(frame: frame, image: image, identity: "id", pixelSize: CGSize(width: 512, height: 1024))

        #expect(small.cacheKey != large.cacheKey)
        #expect(small.canStandInFor(large))
    }

    /// One file name covers two rasters — the editor's 1200 px thumbnail and export's full-resolution
    /// image — so the normalized-texture cache has to key on the source size too.
    @Test func normalizedScreenContentsCachesPerIdentityAndSize() throws {
        let small = try #require(makeTestImage(width: 60, height: 120).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let large = try #require(makeTestImage(width: 120, height: 240).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let identity = "cache-probe-\(UUID().uuidString).png"

        let first = try #require(DeviceModelRenderer.normalizedScreenContents(small, identity: identity))
        let again = try #require(DeviceModelRenderer.normalizedScreenContents(small, identity: identity))
        #expect(first === again)

        let resized = try #require(DeviceModelRenderer.normalizedScreenContents(large, identity: identity))
        #expect(resized !== first)

        let uncached = try #require(DeviceModelRenderer.normalizedScreenContents(small, identity: nil))
        #expect(uncached !== first, "Without an identity there is nothing to cache under")
    }

    /// Export reads the untouched PNG; the editor holds a thumbnail `EditorImagePresentation` already
    /// moved to sRGB. Under ~1200 px those share a file name *and* a pixel size, so letting export into
    /// the texture cache would hand it the editor's converted bytes.
    @Test func exportWithholdsTheScreenTextureCacheIdentity() throws {
        let frame = try modelFrame()
        let image = makeTestImage(width: 1320, height: 2868)

        func request(isExport: Bool) -> DeviceModelSnapshotRequest {
            DeviceModelSnapshotRequest.make(
                frame: frame,
                width: 330,
                height: 717,
                isExport: isExport,
                screenshotImage: image,
                screenshotImageIdentity: "shot.png",
                pitch: 0,
                yaw: 0,
                bodyMaterial: DeviceBodyMaterial(),
                lighting: DeviceLighting(),
                bodyColor: .black
            )
        }

        #expect(request(isExport: false).screenContentsIdentity == "shot.png")
        #expect(request(isExport: true).screenContentsIdentity == nil)
    }

    /// `clonedBaseScene` reads a cached `SCNScene` — a shared node graph whose bounding boxes
    /// SceneKit memoizes lazily — and is reachable from the snapshot actor and the main actor at
    /// once (export's synchronous path, and prewarm racing a visible device on project open). This
    /// interleaves both deliberately. A smoke test, not a proof: it exercises the shape that was
    /// unguarded, and fails loudly if the lock is ever removed.
    @Test func concurrentSceneBuildsFromBothExecutorsAllSucceed() async throws {
        let frame = try modelFrame()
        let spec = try #require(frame.modelSpec)
        let expected = DeviceModelRenderer.snapshotPixelSize(width: 330, height: 717, isExport: false)

        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<3 {
                group.addTask { await DeviceModelSnapshotQueue.shared.snapshot(self.request(frame: frame)) != nil }
            }
            group.addTask { await DeviceModelSnapshotQueue.shared.prewarm([spec, spec]); return true }
            for _ in 0..<2 {
                group.addTask { @MainActor in
                    guard let image = DeviceModelRenderer.snapshotDeviceModel(self.request(frame: frame)) else {
                        return false
                    }
                    return image.width == Int(expected.width) && image.height == Int(expected.height)
                }
            }
            for await ok in group {
                #expect(ok, "A concurrent scene build failed or came back the wrong size")
            }
        }
    }
}
