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
    @Environment(\.isExportRendering) private var isExportRendering
    @State private var renderedSnapshotKey: DeviceModelRenderer.SnapshotKey?
    @State private var renderedSnapshotImage: NSImage?

    private var effectiveSnapshotScale: CGFloat {
        DeviceModelRenderer.snapshotScale(width: width, height: height, isExport: isExportRendering)
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
            if isExportRendering {
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
            width: width,
            height: height,
            scale: effectiveSnapshotScale,
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
        return DeviceModelRenderer.cachedSnapshot(for: key)
    }

    private func synchronousSnapshot(for key: DeviceModelRenderer.SnapshotKey) -> NSImage? {
        if let cached = DeviceModelRenderer.cachedSnapshot(for: key) {
            return cached
        }
        guard let rendered = DeviceModelRenderer.snapshotDeviceModel(
            frame: frame,
            width: width,
            height: height,
            scale: effectiveSnapshotScale,
            screenshotImage: screenshotImage,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTintColor: NSColor(bodyColor)
        ) else { return nil }
        DeviceModelRenderer.storeSnapshot(rendered, for: key)
        return rendered
    }

    private func renderSnapshotIfNeeded(for key: DeviceModelRenderer.SnapshotKey) async {
        if let cached = DeviceModelRenderer.cachedSnapshot(for: key) {
            renderedSnapshotKey = key
            renderedSnapshotImage = cached
            return
        }

        guard let rendered = DeviceModelRenderer.snapshotDeviceModel(
            frame: frame,
            width: width,
            height: height,
            scale: effectiveSnapshotScale,
            screenshotImage: screenshotImage,
            pitch: pitch,
            yaw: yaw,
            bodyMaterial: bodyMaterial,
            lighting: lighting,
            bodyTintColor: NSColor(bodyColor)
        ), !Task.isCancelled else { return }

        DeviceModelRenderer.storeSnapshot(rendered, for: key)
        renderedSnapshotKey = key
        renderedSnapshotImage = rendered
    }

}
