import SwiftUI

/// The new-row preferences from Settings. The caller reads them, so the factory below stays free
/// of `UserDefaults`.
struct NewRowDefaults {
    var size: (width: CGFloat, height: CGFloat)?
    var templateCount: Int
    var deviceCategory: DeviceCategory?
    var deviceFrameId: String?
}

extension ScreenshotRow {
    static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    /// A fresh row: explicit arguments win over `defaults`, which win over the built-in 1242×2688.
    static func makeDefault(
        id: UUID = UUID(),
        label: String? = nil,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        templateCount: Int? = nil,
        deviceCategory: DeviceCategory? = nil,
        deviceFrameId: String? = nil,
        defaults: NewRowDefaults
    ) -> ScreenshotRow {
        let w: CGFloat = width ?? defaults.size?.width ?? 1242
        let h: CGFloat = height ?? defaults.size?.height ?? 2688
        let resolvedTemplateCount = templateCount ?? defaults.templateCount
        let templates = (0..<resolvedTemplateCount).map { index in
            ScreenshotTemplate(backgroundColor: templateColors[index % templateColors.count])
        }
        let resolvedDeviceCategory = deviceCategory ?? defaults.deviceCategory
        let resolvedDeviceFrame = deviceFrameId ?? defaults.deviceFrameId
        let resolvedFrame = resolvedDeviceFrame.flatMap { DeviceFrameCatalog.frame(for: $0) }

        var shapes: [CanvasShapeModel] = []
        if let resolvedDeviceCategory {
            shapes = (0..<resolvedTemplateCount).map { index in
                var device = CanvasShapeModel.defaultDevice(
                    centerX: CGFloat(index) * w + w / 2,
                    centerY: h / 2,
                    templateHeight: h,
                    category: resolvedDeviceCategory
                )
                if let resolvedFrame {
                    device.deviceCategory = resolvedFrame.fallbackCategory
                    device.deviceFrameId = resolvedFrame.id
                    device.adjustToDeviceAspectRatio(centerX: CGFloat(index) * w + w / 2)
                }
                return device
            }
        }
        return ScreenshotRow(
            id: id,
            label: label ?? presetLabel(forWidth: w, height: h),
            templates: templates,
            templateWidth: w,
            templateHeight: h,
            defaultDeviceCategory: resolvedDeviceCategory,
            defaultDeviceFrameId: resolvedDeviceFrame,
            shapes: shapes,
            isLabelManuallySet: label != nil
        )
    }
}
