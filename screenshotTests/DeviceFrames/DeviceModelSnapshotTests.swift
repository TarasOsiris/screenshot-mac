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
            DeviceModelFrameView.snapshotDeviceModel(
                frame: frame,
                width: 330,
                height: 717,
                scale: 2,
                screenshotImage: makeTestImage(width: 1320, height: 2868),
                pitch: 0,
                yaw: 0,
                bodyMaterial: DeviceBodyMaterial(),
                lighting: DeviceLighting()
            ),
            "Device model snapshot returned nil"
        )
        #expect(maxAlpha(of: image) > 0, "Snapshot was fully transparent — the device did not render")
    }

    @Test func rotatedSnapshotRendersVisiblePixels() throws {
        let frame = try modelFrame()
        let image = try #require(
            DeviceModelFrameView.snapshotDeviceModel(
                frame: frame,
                width: 330,
                height: 717,
                scale: 2,
                screenshotImage: makeTestImage(width: 1320, height: 2868),
                pitch: 12,
                yaw: -18,
                bodyMaterial: DeviceBodyMaterial(),
                lighting: DeviceLighting()
            )
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

        let withDevice = try bitmap(of: ExportService.renderSingleTemplateImage(
            index: 0, row: row, screenshotImages: images
        ))
        let withoutDevice = try bitmap(of: ExportService.renderSingleTemplateImage(
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

    // MARK: - Helpers

    private func key(frame: DeviceFrame, image: NSImage?, identity: String?) -> DeviceModelFrameView.SnapshotKey {
        DeviceModelFrameView.snapshotKey(
            frame: frame,
            width: 330,
            height: 717,
            scale: 2,
            screenshotImage: image,
            screenshotImageIdentity: identity,
            pitch: 0,
            yaw: 0,
            bodyMaterial: DeviceBodyMaterial(),
            lighting: DeviceLighting(),
            bodyColor: .black
        )
    }

    private func maxAlpha(of image: NSImage) -> Int {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
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
}
