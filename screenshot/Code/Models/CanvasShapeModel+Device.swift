import Foundation
import SwiftUI

extension CanvasShapeModel {
    func resolvedDeviceBodyColor(default defaultColor: Color) -> Color {
        if let override = deviceBodyColorData?.color { return override }
        if supportsDeviceModelRotation { return Self.defaultDevice3DBodyColor }
        if deviceCategory == .pixel9 { return Self.defaultPixel9BodyColor }
        return defaultColor
    }

    var supportsDeviceModelRotation: Bool {
        type == .device && (resolvedDeviceFrame?.isModelBacked == true)
    }

    var resolvedDevicePitch: Double {
        guard supportsDeviceModelRotation else { return 0 }
        return devicePitch ?? resolvedDeviceFrame?.modelSpec?.defaultPitch ?? Self.defaultDeviceModelPitch
    }

    var resolvedDeviceYaw: Double {
        guard supportsDeviceModelRotation else { return 0 }
        return deviceYaw ?? resolvedDeviceFrame?.modelSpec?.defaultYaw ?? Self.defaultDeviceModelYaw
    }

    mutating func resetDeviceModelRotation() {
        devicePitch = nil
        deviceYaw = nil
    }

    var resolvedDeviceBodyMaterial: DeviceBodyMaterial {
        deviceBodyMaterial ?? DeviceBodyMaterial()
    }

    mutating func resetDeviceBodyMaterial() {
        deviceBodyMaterial = nil
    }

    var resolvedDeviceLighting: DeviceLighting {
        deviceLighting ?? DeviceLighting()
    }

    mutating func resetDeviceLighting() {
        deviceLighting = nil
    }

    var resolvedDeviceFrame: DeviceFrame? {
        guard let frameId = deviceFrameId else { return nil }
        return DeviceFrameCatalog.frame(for: frameId)
    }

    /// Resolved base dimensions accounting for real device frames.
    var resolvedBaseDimensions: (width: CGFloat, height: CGFloat) {
        if let frame = resolvedDeviceFrame {
            return frame.baseDimensions
        }
        return (deviceCategory ?? .iphone).baseDimensions
    }

    /// Abstract device frames (no specific catalog frame) that size themselves to the user's
    /// screenshot aspect instead of a fixed device aspect. These must not be re-normalized to a
    /// fixed aspect on export, or the editor and exported image diverge.
    var flexesToImageAspect: Bool {
        deviceFrameId == nil
            && (deviceCategory == .invisible
                || deviceCategory == .androidPhone
                || deviceCategory == .androidTablet)
    }

    /// Selects an abstract device category (no specific frame).
    /// When switching to `.invisible`, pass the current screenshot image size so the frame
    /// adapts its aspect ratio to the image. A nice default corner radius is also applied.
    mutating func selectAbstractDevice(_ category: DeviceCategory, screenshotImageSize: CGSize? = nil) {
        deviceFrameId = nil
        deviceCategory = category
        deviceBodyColorData = nil
        resetDeviceModelRotation()
        resetDeviceBodyMaterial()
        resetDeviceLighting()
        if category == .invisible {
            if borderRadius == 0 {
                borderRadius = 40
            }
            if let imageSize = screenshotImageSize {
                adaptToImageAspectRatio(imageSize)
            }
        } else {
            adjustToDeviceAspectRatio()
        }
    }

    /// Adjusts width to match the given image's aspect ratio, keeping the shape centered horizontally.
    mutating func adaptToImageAspectRatio(_ imageSize: CGSize) {
        guard imageSize.width > 0 && imageSize.height > 0 else { return }
        let aspect = imageSize.width / imageSize.height
        let centerX = x + width / 2
        width = height * aspect
        x = centerX - width / 2
    }

    /// Selects a specific device frame from the catalog.
    mutating func selectRealFrame(_ frame: DeviceFrame) {
        deviceCategory = frame.fallbackCategory
        deviceFrameId = frame.id
        if !frame.isModelBacked {
            resetDeviceModelRotation()
            resetDeviceBodyMaterial()
            resetDeviceLighting()
        }
        adjustToDeviceAspectRatio()
    }

    /// Adjusts the shape to match the correct aspect ratio for the current device type.
    /// Preserves the longer of the existing dimensions so an orientation flip keeps the
    /// shape's visual size — only the short side and orientation change. Re-centers on Y;
    /// optionally re-centers horizontally at `centerX`.
    /// Invisible frames skip aspect ratio enforcement — they keep their current dimensions.
    mutating func adjustToDeviceAspectRatio(centerX: CGFloat? = nil) {
        if deviceCategory == .invisible && deviceFrameId == nil {
            if let cx = centerX { x = cx - width / 2 }
            return
        }
        let base = resolvedBaseDimensions
        let aspect = base.width / base.height
        let oldCenterY = y + height / 2
        let longSide = max(width, height)
        let shortSide = longSide * min(aspect, 1 / aspect)
        (width, height) = aspect >= 1 ? (longSide, shortSide) : (shortSide, longSide)
        if let cx = centerX {
            x = cx - width / 2
        }
        y = oldCenterY - height / 2
    }

    static func defaultDevice(centerX: CGFloat, centerY: CGFloat, templateHeight: CGFloat = 2688, category: DeviceCategory = .iphone) -> CanvasShapeModel {
        let dims = category.baseDimensions
        // Device should fill ~80% of template height, like typical App Store screenshots
        let h = templateHeight * 0.8
        let scale = h / dims.height
        let w = dims.width * scale
        return CanvasShapeModel(
            type: .device, x: centerX - w / 2, y: centerY - h / 2,
            width: w, height: h,
            color: .clear, deviceCategory: category,
            shadow: .medium
        )
    }

    /// Creates a device shape using the row's default device settings.
    /// If `detectedCategory` is provided, it overrides the row default category
    /// (but a row-level real device frame still takes priority).
    static func defaultDeviceFromRow(_ row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat, detectedCategory: DeviceCategory? = nil) -> CanvasShapeModel {
        let category = detectedCategory ?? row.defaultDeviceCategory ?? .iphone
        var shape = defaultDevice(
            centerX: centerX, centerY: centerY,
            templateHeight: row.templateHeight,
            category: category
        )
        // Only apply the row's default frame if it matches the detected category
        if let frameId = row.defaultDeviceFrameId,
           let frame = DeviceFrameCatalog.frame(for: frameId),
           detectedCategory == nil || frame.fallbackCategory == detectedCategory {
            shape.deviceCategory = frame.fallbackCategory
            shape.deviceFrameId = frame.id
            shape.adjustToDeviceAspectRatio(centerX: centerX)
        }
        return shape
    }
}
