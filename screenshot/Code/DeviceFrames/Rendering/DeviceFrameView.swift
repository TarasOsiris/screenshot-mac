import AppKit
import SwiftUI

enum DeviceModelRenderingMode: Sendable {
    case snapshot
    case live
}

struct DeviceFrameView: View {
    let category: DeviceCategory
    let bodyColor: Color
    let width: CGFloat
    let height: CGFloat
    var screenshotImage: NSImage? = nil
    var deviceFrameId: String? = nil
    var devicePitch: Double = 0
    var deviceYaw: Double = 0
    var bodyMaterial: DeviceBodyMaterial = DeviceBodyMaterial()
    var lighting: DeviceLighting = DeviceLighting()
    var modelRenderingMode: DeviceModelRenderingMode = .snapshot
    var invisibleCornerRadius: CGFloat = 0
    var invisibleOutlineWidth: CGFloat = 0
    var invisibleOutlineColor: Color = .black

    var body: some View {
        if let frameId = deviceFrameId,
           let frame = DeviceFrameCatalog.frame(for: frameId) {
            frameRenderer(for: frame)
        } else {
            fallbackRenderer(category: category)
        }
    }

    @ViewBuilder
    private func frameRenderer(for frame: DeviceFrame) -> some View {
        if frame.isModelBacked {
            DeviceModelFrameView(
                frame: frame,
                bodyColor: bodyColor,
                width: width,
                height: height,
                screenshotImage: screenshotImage,
                pitch: devicePitch,
                yaw: deviceYaw,
                bodyMaterial: bodyMaterial,
                lighting: lighting,
                modelRenderingMode: modelRenderingMode,
                invisibleCornerRadius: invisibleCornerRadius,
                invisibleOutlineWidth: invisibleOutlineWidth,
                invisibleOutlineColor: invisibleOutlineColor
            )
        } else {
            DeviceFrameImageView(
                frame: frame,
                width: width,
                height: height,
                screenshotImage: screenshotImage
            )
        }
    }

    private func fallbackRenderer(category: DeviceCategory) -> some View {
        ProgrammaticDeviceFrameView(
            category: category,
            bodyColor: bodyColor,
            width: width,
            height: height,
            screenshotImage: screenshotImage,
            invisibleCornerRadius: invisibleCornerRadius,
            invisibleOutlineWidth: invisibleOutlineWidth,
            invisibleOutlineColor: invisibleOutlineColor
        )
    }
}
