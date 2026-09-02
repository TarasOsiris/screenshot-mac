#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Metal
import os
import SceneKit
import SwiftUI

struct DeviceModelFrameView: View {

    let frame: DeviceFrame
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    let screenshotImage: NSImage?
    let screenshotImageIdentity: String?
    let pitch: Double
    let yaw: Double
    let bodyMaterial: DeviceBodyMaterial
    let lighting: DeviceLighting
    let modelRenderingMode: DeviceModelRenderingMode
    let invisibleCornerRadius: CGFloat
    let invisibleOutlineWidth: CGFloat
    let invisibleOutlineColor: Color
    @Environment(\.rasterRenderContext) private var renderContext
    @State private var renderedSnapshotKey: DeviceModelRenderer.SnapshotKey?
    @State private var renderedSnapshotImage: NSImage?

    private static let staleRenderDebounce: Duration = .milliseconds(80)

    /// Both offscreen contexts share the pixel budget and the withheld texture identity; only the
    /// cache key tells them apart, so a project card can never define an export's bytes.
    private var isOffscreen: Bool { renderContext != .canvas }

    private var snapshotRequest: DeviceModelSnapshotRequest {
        DeviceModelSnapshotRequest.make(
            frame: frame,
            width: width,
            height: height,
            isExport: isOffscreen,
            screenshotImage: screenshotImage,
            screenshotImageIdentity: screenshotImageIdentity,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyColor: bodyColor
        )
    }

    var body: some View {
        switch modelRenderingMode {
        case .live:
            LiveDeviceModelView(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                screenshotImageIdentity: screenshotImageIdentity,
                pitch: pitch,
                yaw: yaw,
                bodyMaterial: bodyMaterial,
                lighting: lighting,
                bodyTintColor: NSColor(bodyColor)
            )
            .frame(width: width, height: height)
        case .snapshot:
            if isOffscreen {
                synchronousSnapshotView
            } else {
                snapshotView
            }
        }
    }

    private var fallbackView: some View {
        ProgrammaticDeviceFrameView(
            category: frame.fallbackCategory,
            bodyColor: bodyColor,
            width: width,
            height: height,
            screenshotImage: screenshotImage,
            invisibleCornerRadius: invisibleCornerRadius,
            invisibleOutlineWidth: invisibleOutlineWidth,
            invisibleOutlineColor: invisibleOutlineColor
        )
    }

    private var currentSnapshotKey: DeviceModelRenderer.SnapshotKey {
        DeviceModelRenderer.snapshotKey(
            frame: frame,
            renderContext: renderContext,
            pixelSize: DeviceModelRenderer.snapshotPixelSize(
                width: width,
                height: height,
                isExport: isOffscreen
            ),
            screenshotImage: screenshotImage,
            screenshotImageIdentity: screenshotImageIdentity,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyColor: bodyColor
        )
    }

    @ViewBuilder
    private var snapshotView: some View {
        let key = currentSnapshotKey

        if let image = snapshotImage(for: key) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .task(id: key) {
                    await renderSnapshotIfNeeded(for: key)
                }
        } else {
            fallbackView
                .task(id: key) {
                    await renderSnapshotIfNeeded(for: key)
                }
        }
    }

    @ViewBuilder
    private var synchronousSnapshotView: some View {
        let key = currentSnapshotKey

        if let image = synchronousSnapshot(for: key) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
        } else {
            fallbackView
        }
    }

    private func snapshotImage(for key: DeviceModelRenderer.SnapshotKey) -> NSImage? {
        if renderedSnapshotKey == key, let renderedSnapshotImage {
            return renderedSnapshotImage
        }
        if let cached = DeviceModelRenderer.cachedSnapshot(for: key) {
            return cached
        }
        // Rendering is asynchronous now, so a key change would otherwise swap in the abstract
        // fallback — which is drawn front-on, so a pitched device appears to snap flat and back.
        // The previous raster is the same device one state behind; `.resizable()` below covers a
        // density difference, and a render that actually fails clears it rather than pinning a pose.
        if let renderedSnapshotImage, renderedSnapshotKey?.canStandInFor(key) == true {
            return renderedSnapshotImage
        }
        return nil
    }

    /// Export must stay synchronous: it is one `ImageRenderer`/`cacheDisplay` pass over a view that
    /// never enters a hierarchy, so `.task` never fires and an `await` would bake the wireframe
    /// fallback into the exported PNG.
    private func synchronousSnapshot(for key: DeviceModelRenderer.SnapshotKey) -> NSImage? {
        if let cached = DeviceModelRenderer.cachedSnapshot(for: key) {
            return cached
        }
        let request = snapshotRequest
        guard let rendered = DeviceModelRenderer.snapshotDeviceModel(request) else { return nil }
        let image = NSImage(cgImage: rendered, size: request.pointSize)
        DeviceModelRenderer.storeSnapshot(image, for: key)
        return image
    }

    private func renderSnapshotIfNeeded(for key: DeviceModelRenderer.SnapshotKey) async {
        if let cached = DeviceModelRenderer.cachedSnapshot(for: key) {
            renderedSnapshotKey = key
            renderedSnapshotImage = cached
            return
        }

        // Only a zoom sweep waits: it re-keys every device in the row at once, so the queue would
        // fill with rasters no one will see. A pose or content change moves one shape, and
        // `.task(id:)` cancellation already drops whatever it superseded. Waiting on a pose starved
        // the rotation sliders outright — they tick every ~33 ms, faster than this delay.
        if renderedSnapshotImage != nil, renderedSnapshotKey?.matchesIgnoringPixelSize(key) == true {
            try? await Task.sleep(for: Self.staleRenderDebounce)
            guard !Task.isCancelled else { return }
        }

        let request = snapshotRequest
        guard let rendered = await DeviceModelSnapshotQueue.shared.snapshot(request) else {
            // A cancelled render is superseded by the next key. A real failure must drop the stale
            // raster, or `canStandInFor` keeps presenting the previous pose as though it were live.
            if !Task.isCancelled, renderedSnapshotKey != nil {
                renderedSnapshotKey = nil
                renderedSnapshotImage = nil
            }
            return
        }
        // Cached before the cancellation check, not after: a superseded render is still a correct
        // raster for its key, and a rotation slider swings back across poses it just paid for.
        let image = NSImage(cgImage: rendered, size: request.pointSize)
        DeviceModelRenderer.storeSnapshot(image, for: key)

        guard !Task.isCancelled else { return }
        renderedSnapshotKey = key
        renderedSnapshotImage = image
    }

}
