#if os(macOS)
import AppKit
#else
import UIKit
#endif
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
    var screenshotImage: NSImage?
    var screenshotImageIdentity: String?
    var deviceFrameId: String?
    var devicePitch: Double = 0
    var deviceYaw: Double = 0
    var bodyMaterial: DeviceBodyMaterial = DeviceBodyMaterial()
    var lighting: DeviceLighting = DeviceLighting()
    var modelRenderingMode: DeviceModelRenderingMode = .snapshot
    var invisibleCornerRadius: CGFloat = 0
    var invisibleOutlineWidth: CGFloat = 0
    var invisibleOutlineColor: Color = .black
    var hideCameraCutout: Bool = false

    /// How far the screen's center sits from the frame's; a 3D model's screen moves with its pose, so it stays at zero.
    var screenOffset: CGSize {
        let size = CGSize(width: width, height: height)
        guard let frame = deviceFrameId.flatMap({ DeviceFrameCatalog.frame(for: $0) }) else {
            return ProgrammaticDeviceFrameView.screenOffset(category: category, in: size)
        }
        guard !frame.isModelBacked else { return .zero }
        let screen = frame.spec.screenRect(in: size)
        return CGSize(width: screen.midX - width / 2, height: screen.midY - height / 2)
    }

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
                screenshotImageIdentity: screenshotImageIdentity,
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
            invisibleOutlineColor: invisibleOutlineColor,
            hideCameraCutout: hideCameraCutout
        )
    }
}
