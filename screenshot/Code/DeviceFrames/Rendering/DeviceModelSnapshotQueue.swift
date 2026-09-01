#if os(macOS)
import AppKit
#else
import UIKit
#endif
import CoreGraphics
import SceneKit
import SwiftUI

/// A body colour the caller already resolved on its own actor.
///
/// A SwiftUI `Color` — and any dynamic `NSColor` — resolves against the *calling thread's*
/// appearance, so it has to be flattened to components before it can cross to the render executor.
/// These are the same sRGB components `SnapshotKey` is built from, so the tint and the cache key
/// can never disagree.
nonisolated struct DeviceBodyTint: Sendable, Hashable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    @MainActor
    init(_ color: Color) {
        let components = color.sRGBComponents
        red = components.r
        green = components.g
        blue = components.b
        alpha = components.a
    }

    var platformColor: NSColor {
        #if os(macOS)
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
        #else
        NSColor(red: red, green: green, blue: blue, alpha: alpha)
        #endif
    }
}

/// Everything one offscreen device render needs, in a form that can cross actors.
///
/// Built by `make(...)` on the main actor, because reading it touches things that must be read
/// there: `DeviceBodyMaterial`/`DeviceLighting` come off the document, the body colour has to
/// resolve against this thread's appearance, and the screenshot's `CGImage` has to be pulled off a
/// non-`Sendable` `NSImage`.
nonisolated struct DeviceModelSnapshotRequest: Sendable {
    let frame: DeviceFrame
    let pixelSize: CGSize
    let pointSize: CGSize
    let screenContents: CGImage?
    /// The document's file name for `screenContents`, so the renderer can cache the normalized
    /// texture instead of redrawing it on every pose tick. **Editor only** — see `make`.
    let screenContentsIdentity: String?
    let pitch: Double
    let yaw: Double
    let bodyMaterial: DeviceBodyMaterial
    let lighting: DeviceLighting
    let bodyTint: DeviceBodyTint?

    /// The single place the pixel box is derived, shared by the editor and the exporter so the two
    /// cannot round it differently.
    @MainActor
    static func make(
        frame: DeviceFrame,
        width: CGFloat,
        height: CGFloat,
        isExport: Bool,
        screenshotImage: NSImage?,
        screenshotImageIdentity: String? = nil,
        pitch: Double,
        yaw: Double,
        bodyMaterial: DeviceBodyMaterial,
        lighting: DeviceLighting,
        bodyColor: Color?
    ) -> DeviceModelSnapshotRequest {
        DeviceModelSnapshotRequest(
            frame: frame,
            pixelSize: DeviceModelRenderer.snapshotPixelSize(width: width, height: height, isExport: isExport),
            pointSize: CGSize(width: max(1, width), height: max(1, height)),
            screenContents: DeviceModelRenderer.screenContents(from: screenshotImage),
            // Withheld on export, which loads the untouched PNG while the editor holds a thumbnail
            // that `EditorImagePresentation` already moved to sRGB. Under ~1200 px the two share both
            // a file name and a pixel size, so a shared cache would hand export the editor's
            // converted texture and move the exported bytes.
            screenContentsIdentity: isExport || screenshotImage == nil ? nil : screenshotImageIdentity,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTint: bodyColor.map(DeviceBodyTint.init)
        )
    }
}

/// Serializes every offscreen SceneKit render onto one executor off the main actor.
///
/// The editor used to render these inside `.task`, which — under this target's default MainActor
/// isolation — ran the whole synchronous SceneKit pass as one uninterrupted main-actor job. A
/// scrollbar-drag trace showed three of them costing 62/15/17 ms in the middle of the first scroll.
///
/// Deliberately an `actor` and not `@concurrent`: parallel snapshots would mean concurrent Metal
/// command buffers and concurrent 4×-MSAA targets for one GPU, and would be the only concurrent
/// readers of the shared base scenes. Serial is safer and no slower. An actor's own methods always
/// hop to its executor — `NonisolatedNonsendingByDefault` only rewrites `nonisolated async func` —
/// so this genuinely leaves the main thread.
actor DeviceModelSnapshotQueue {
    static let shared = DeviceModelSnapshotQueue()

    /// Reused so Metal's command queue and compiled-shader cache survive between renders; safe
    /// only because the actor guarantees one render at a time.
    private lazy var renderer = SCNRenderer(device: DeviceModelRenderer.sharedMetalDevice, options: nil)

    /// `Task.isCancelled` reflects the *calling* task here, so a device that scrolled away or whose
    /// key changed drops its queued render before it starts rather than stacking behind the others.
    func snapshot(_ request: DeviceModelSnapshotRequest) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return DeviceModelRenderer.snapshotDeviceModel(request, using: renderer)
    }

    /// Parses each USDZ into the shared scene cache. Off the scroll path, so the ~26 ms ModelIO
    /// parse is not paid inside the first render of a freshly opened project.
    ///
    /// Capped at what the cache holds — warming more evicts the early ones before anything asks —
    /// and yields between specs, because an actor method with no suspension point holds the serial
    /// executor for its whole run: without the yield every visible device would sit on its
    /// wireframe fallback until the last parse finished.
    func prewarm(_ modelSpecs: [DeviceFrameModelSpec]) async {
        for spec in modelSpecs.prefix(DeviceModelRenderer.modelSceneCacheLimit) {
            guard !Task.isCancelled else { return }
            DeviceModelRenderer.prewarmModelScene(for: spec)
            await Task.yield()
        }
    }
}
