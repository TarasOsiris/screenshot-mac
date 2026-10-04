import SwiftUI

struct CanvasShapeRenderContent: View {
    let shape: CanvasShapeModel
    let effectiveW: CGFloat
    let effectiveH: CGFloat
    let displayW: CGFloat
    let displayH: CGFloat
    let displayScale: CGFloat
    let displayOutlineWidth: CGFloat
    var screenshotImage: NSImage?
    var screenshotImageIdentity: String?
    var imageCrop: ImageCrop?
    var isCropping = false
    /// A resize drag is in progress: every tick is a new box, so nothing it measures is worth caching.
    var isResizing = false
    /// A crop handle or pan is in flight: the rule-of-thirds grid shows over the window.
    var showsCropGrid = false
    var resourceState: CanvasResourceState = .satisfied
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color
    var deviceModelRenderingMode: DeviceModelRenderingMode
    var cachedSvgImage: NSImage?
    var allowSynchronousSvgRender = true
    let showsEditorHelpers: Bool
    let isEditingText: Bool
    @Binding var editingTextValue: String
    @Binding var editingRichTextData: String?
    @Binding var isDropTargeted: Bool
    let onRequestImagePicker: () -> Void
    let onHandleDrop: ([NSItemProvider]) -> Bool
    let onCommitTextEdit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)?
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)?
    var formatController: RichTextFormatController?
    let resolveNSFont: (CGFloat, NSFont.Weight, Bool) -> NSFont
    let fontWeightResolver: (Int) -> Font.Weight
    let renderSvgImage: (String, Bool, Color, CGSize?) -> NSImage?
    @Environment(\.displayScale) private var screenScale
    @Environment(\.isLiveShapeEdit) private var isLiveShapeEdit

    var body: some View {
        shapeContent
            .modifier(ShadowModifier(
                shadow: shape.shadow,
                displayScale: displayScale,
                rotationDegrees: shape.rotation
            ))
    }

    @ViewBuilder
    private var shapeContent: some View {
        switch shape.type {
        case .rectangle:
            let maxRadius = min(displayW, displayH) / 2
            let clampedRadius = min(shape.borderRadius * displayScale, maxRadius)
            outlinedShape(RoundedRectangle(cornerRadius: clampedRadius, style: .circular))

        case .circle:
            outlinedShape(Ellipse())

        case .star:
            outlinedShape(StarShape(pointCount: shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount))

        case .text:
            if isEditingText {
                textEditor
            } else {
                displayTextContent
            }

        case .image:
            imageContent

        case .svg:
            svgContent

        case .device:
            deviceContent
        }
    }

    var isLiveTextLayout: Bool { isLiveShapeEdit || isResizing }

    /// Extra resolution for the editor only. Preview and export draw at model scale using the
    /// historical platform default, so changing that factor would move exported bytes. The editor
    /// instead scales the raster by `displayScale` — a downscale for a tall App Store template, but
    /// an *upscale* on a short one at high zoom, which is what this covers.
    var textRenderScale: CGFloat {
        guard showsEditorHelpers else { return TextLayoutStyle.defaultTextRenderScale }
        return TextLayoutStyle.quantizedTextRenderScale(displayScale * max(screenScale, 1))
    }

    @ViewBuilder
    private var svgContent: some View {
        let svg = shape.svgContent ?? ""
        let useColor = shape.svgUseColor == true
        let targetSize = CGSize(width: effectiveW, height: effectiveH)
        let cachedImage = cachedSvgImage ?? SvgHelper.cachedRender(
            from: svg,
            useColor: useColor,
            color: shape.color,
            targetSize: targetSize
        )
        let image = cachedImage ?? (allowSynchronousSvgRender
            ? renderSvgImage(svg, useColor, shape.color, targetSize)
            : nil)

        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 4 * displayScale)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    if showsEditorHelpers {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 24 * displayScale))
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    @ViewBuilder
    private var deviceContent: some View {
        let isInvisible = shape.deviceCategory == .invisible
        let frame = DeviceFrameView(
            category: shape.deviceCategory ?? .iphone,
            bodyColor: shape.resolvedDeviceBodyColor(default: defaultDeviceBodyColor),
            width: displayW,
            height: displayH,
            screenshotImage: screenshotImage,
            screenshotImageIdentity: screenshotImageIdentity,
            deviceFrameId: shape.deviceFrameId,
            devicePitch: shape.resolvedDevicePitch,
            deviceYaw: shape.resolvedDeviceYaw,
            bodyMaterial: shape.resolvedDeviceBodyMaterial,
            lighting: shape.resolvedDeviceLighting,
            modelRenderingMode: deviceModelRenderingMode,
            invisibleCornerRadius: isInvisible ? shape.borderRadius * displayScale : 0,
            invisibleOutlineWidth: isInvisible ? max(0, (shape.outlineWidth ?? 0) * displayScale) : 0,
            invisibleOutlineColor: isInvisible ? (shape.outlineColor ?? CanvasShapeModel.defaultOutlineColor) : .black,
            hideCameraCutout: shape.hideCameraCutout ?? false
        )

        withImageDropAffordances(frame, screenOffset: frame.screenOffset)
    }

    @ViewBuilder
    private func outlinedShape<S: InsettableShape>(_ outline: S) -> some View {
        let inset = clampedOutlineInset
        if let outlineColor = shape.outlineColor, inset > 0 {
            ZStack {
                outline.fill(outlineColor)
                filledShape(outline.inset(by: inset))
            }
            .clipShape(outline)
        } else {
            filledShape(outline)
        }
    }

    @ViewBuilder
    private func filledShape<S: Shape>(_ outline: S) -> some View {
        if shape.resolvedFillStyle == .color {
            outline.fill(shape.color)
        } else {
            shape.fillView(image: fillImage, modelSize: CGSize(width: shape.width, height: shape.height))
                .clipShape(outline)
        }
    }

    /// The outline is a band drawn inward from the edge, so it can never exceed half the short side.
    var clampedOutlineInset: CGFloat {
        min(displayOutlineWidth, max(0, min(displayW, displayH) / 2))
    }
}
