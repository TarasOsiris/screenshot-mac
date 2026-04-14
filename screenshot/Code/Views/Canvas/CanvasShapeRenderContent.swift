import SwiftUI
import UniformTypeIdentifiers

struct CanvasShapeRenderContent: View {
    let shape: CanvasShapeModel
    let effectiveW: CGFloat
    let effectiveH: CGFloat
    let displayW: CGFloat
    let displayH: CGFloat
    let displayScale: CGFloat
    let displayOutlineWidth: CGFloat
    var screenshotImage: NSImage?
    var fillImage: NSImage?
    var defaultDeviceBodyColor: Color
    var deviceModelRenderingMode: DeviceModelRenderingMode
    var cachedSvgImage: NSImage?
    let showsEditorHelpers: Bool
    let isEditingText: Bool
    @Binding var editingTextValue: String
    @Binding var editingRichTextData: String?
    @Binding var isDropTargeted: Bool
    let onRequestImagePicker: () -> Void
    let onHandleDrop: ([NSItemProvider]) -> Bool
    let onCommitTextEdit: () -> Void
    var onRichTextChange: ((String?, String) -> Void)? = nil
    var onSelectionChange: (([NSAttributedString.Key: Any]?, NSRange?) -> Void)? = nil
    var formatController: RichTextFormatController? = nil
    let resolveNSFont: (CGFloat, NSFont.Weight, Bool) -> NSFont
    let fontWeightResolver: (Int) -> Font.Weight
    let renderSvgImage: (String, Bool, Color, CGSize?) -> NSImage?

    var body: some View {
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

    private var displayTextContent: some View {
        let rawText = shape.text ?? ""
        let showPlaceholder = showsEditorHelpers && rawText.isEmpty && !shape.hasRichText
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = fontWeightResolver(shape.fontWeight ?? 700)
        let isItalic = showPlaceholder ? true : (shape.italic ?? false)
        let nsFont = resolveNSFont(fontSize, weight.nsWeight, isItalic)
        let displayText = showPlaceholder ? "Text" : rawText
        let nsColor = NSColor(shape.color.opacity(showPlaceholder ? 0.4 : 1.0))
        let align = shape.textAlign.nsTextAlignment
        let verticalAlign = shape.textVerticalAlign ?? .center
        let uppercase = shape.uppercase ?? false
        let richText = showPlaceholder ? nil : shape.richText

        return Group {
            if showsEditorHelpers {
                LiveDisplayTextView(
                    text: displayText,
                    font: nsFont,
                    color: nsColor,
                    alignment: align,
                    verticalAlignment: verticalAlign,
                    uppercase: uppercase,
                    letterSpacing: shape.letterSpacing,
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing,
                    richTextData: richText
                )
            } else {
                RasterizedDisplayTextView(
                    text: displayText,
                    font: nsFont,
                    color: nsColor,
                    alignment: align,
                    verticalAlignment: verticalAlign,
                    uppercase: uppercase,
                    letterSpacing: shape.letterSpacing,
                    lineHeightMultiple: shape.lineHeightMultiple,
                    legacyLineSpacing: shape.lineSpacing,
                    richTextData: richText
                )
            }
        }
        .frame(width: effectiveW, height: effectiveH)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    @ViewBuilder
    private var imageContent: some View {
        if let screenshotImage {
            Image(nsImage: screenshotImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: displayW, height: displayH)
                .clipShape(RoundedRectangle(cornerRadius: shape.borderRadius * displayScale))
        } else if showsEditorHelpers {
            imageDropPlaceholder {
                RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
                    .fill(Color.gray.opacity(0.3))
            }
        }
    }

    @ViewBuilder
    private var svgContent: some View {
        if let image = cachedSvgImage ?? renderSvgImage(
            shape.svgContent ?? "",
            shape.svgUseColor == true,
            shape.color,
            CGSize(width: effectiveW, height: effectiveH)
        ) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
        } else if showsEditorHelpers {
            RoundedRectangle(cornerRadius: 4 * displayScale)
                .fill(Color.gray.opacity(0.2))
                .overlay {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 24 * displayScale))
                        .foregroundStyle(.secondary)
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
            deviceFrameId: shape.deviceFrameId,
            devicePitch: shape.resolvedDevicePitch,
            deviceYaw: shape.resolvedDeviceYaw,
            modelRenderingMode: deviceModelRenderingMode,
            invisibleCornerRadius: isInvisible ? shape.borderRadius * displayScale : 0,
            invisibleOutlineWidth: isInvisible ? max(0, (shape.outlineWidth ?? 0) * displayScale) : 0,
            invisibleOutlineColor: isInvisible ? (shape.outlineColor ?? CanvasShapeModel.defaultOutlineColor) : .black
        )

        if screenshotImage == nil && showsEditorHelpers {
            imageDropPlaceholder { frame }
        } else if showsEditorHelpers {
            frame
                .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                    onHandleDrop(providers)
                }
        } else {
            frame
        }
    }

    private var textEditor: some View {
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = fontWeightResolver(shape.fontWeight ?? 700)
        let nsFont = resolveNSFont(fontSize, weight.nsWeight, shape.italic ?? false)

        return InlineTextEditor(
            text: $editingTextValue,
            font: nsFont,
            color: NSColor(shape.color),
            alignment: shape.textAlign.nsTextAlignment,
            verticalAlignment: shape.textVerticalAlign ?? .center,
            uppercase: shape.uppercase ?? false,
            letterSpacing: shape.letterSpacing,
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            richTextData: editingRichTextData,
            formatController: formatController,
            onCommit: onCommitTextEdit,
            onRichTextChange: onRichTextChange,
            onSelectionChange: onSelectionChange
        )
        .frame(width: effectiveW, height: effectiveH)
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    @ViewBuilder
    private func imageDropPlaceholder<Background: View>(@ViewBuilder background: () -> Background) -> some View {
        let sizeRef = min(displayW, displayH)
        let iconSize = min(28, max(14, sizeRef * 0.18))
        let padding = min(12, max(4, sizeRef * 0.05))
        let cornerRadius = min(8, max(4, sizeRef * 0.04))

        ZStack {
            background()

            Button(action: onRequestImagePicker) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.badge.plus")
                    .font(.system(size: iconSize))
                    .foregroundStyle(.primary)
                    .padding(padding)
                    .background(
                        .thinMaterial.opacity(isDropTargeted ? 0.9 : 1.0),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .focusable(false)
            .animation(.easeInOut(duration: 0.12), value: isDropTargeted)

            if isDropTargeted {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
            }
        }
        .frame(width: displayW, height: displayH)
        .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
            onHandleDrop(providers)
        }
    }

    @ViewBuilder
    private func outlinedShape<S: InsettableShape>(_ outline: S) -> some View {
        let maxInset = max(0, min(displayW, displayH) / 2)
        let inset = min(displayOutlineWidth, maxInset)

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
}
