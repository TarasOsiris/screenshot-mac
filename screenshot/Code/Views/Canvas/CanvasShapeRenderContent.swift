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
        .background { textBackgroundLayer }
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    /// Rounded-rect plate behind a text shape's glyphs. Sized in model space (the `effectiveW/H`
    /// frame) so the enclosing `.scaleEffect(displayScale)` scales the radius for editor/export parity —
    /// the radius is NOT pre-multiplied by displayScale (unlike the rectangle/image cases).
    @ViewBuilder
    private var textBackgroundLayer: some View {
        if let bg = shape.textBackgroundColor {
            // Padding grows the plate outward beyond the text frame (model space → scaled by the
            // enclosing scaleEffect). Corner radius is clamped against the padded dimensions.
            let pad = max(0, shape.textBackgroundPadding ?? 0)
            let plateW = effectiveW + 2 * pad
            let plateH = effectiveH + 2 * pad
            let radius = min(shape.textBackgroundCornerRadius ?? 0, min(plateW, plateH) / 2)
            let plate = RoundedRectangle(cornerRadius: radius, style: .continuous)
            let outlineWidth = min(max(0, shape.textBackgroundOutlineWidth ?? 0), min(plateW, plateH) / 2)

            if let outlineColor = shape.textBackgroundOutlineColor, outlineWidth > 0 {
                ZStack {
                    plate.fill(outlineColor)
                    plate.inset(by: outlineWidth).fill(bg)
                }
                .clipShape(plate)
                .padding(-pad)
            } else {
                plate.fill(bg)
                    .padding(-pad)
            }
        }
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
            bodyMaterial: shape.resolvedDeviceBodyMaterial,
            lighting: shape.resolvedDeviceLighting,
            modelRenderingMode: deviceModelRenderingMode,
            invisibleCornerRadius: isInvisible ? shape.borderRadius * displayScale : 0,
            invisibleOutlineWidth: isInvisible ? max(0, (shape.outlineWidth ?? 0) * displayScale) : 0,
            invisibleOutlineColor: isInvisible ? (shape.outlineColor ?? CanvasShapeModel.defaultOutlineColor) : .black,
            hideCameraCutout: shape.hideCameraCutout ?? false
        )
        .modifier(DeviceShadowModifier(
            shadow: shape.shadow,
            displayScale: displayScale,
            rotationDegrees: shape.rotation
        ))

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

    @ViewBuilder
    private var textEditor: some View {
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        let weight = fontWeightResolver(shape.fontWeight ?? 700)
        let nsFont = resolveNSFont(fontSize, weight.nsWeight, shape.italic ?? false)

        // iPad renders the editor at display scale (font × displayScale in a display-size frame)
        // so the UITextView's selection handles are screen-sized; macOS keeps model scale +
        // scaleEffect since selection there is mouse-based.
        #if os(iOS)
        let editorScale = displayScale
        #else
        let editorScale: CGFloat = 1
        #endif

        let editor = InlineTextEditor(
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
            renderScale: editorScale,
            formatController: formatController,
            onCommit: onCommitTextEdit,
            onRichTextChange: onRichTextChange,
            onSelectionChange: onSelectionChange
        )

        #if os(iOS)
        editor.frame(width: displayW, height: displayH, alignment: .topLeading)
        #else
        editor
            .frame(width: effectiveW, height: effectiveH)
            .background { textBackgroundLayer }
            .scaleEffect(displayScale, anchor: .topLeading)
            .frame(width: displayW, height: displayH, alignment: .topLeading)
        #endif
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

/// True while a view is being rasterized offscreen (`ExportService.renderViewToImage`)
/// rather than composited live on screen. Used to compensate for AppKit's flipped-view
/// shadow handling. Defaults to false (live rendering).
private struct ExportRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isExportRendering: Bool {
        get { self[ExportRenderingKey.self] }
        set { self[ExportRenderingKey.self] = newValue }
    }
}

/// Applies a device's configurable drop shadow.
///
/// `.compositingGroup()` flattens the device frame's sub-layers (screenshot + bezel, or
/// programmatic body parts) into one image first, so exactly one drop shadow is cast from
/// the unified silhouette — strictly behind the whole device. Without it, SwiftUI casts a
/// shadow per sub-layer and the screenshot's own offset shadow bleeds *inside* the frame.
///
/// Offscreen flip: SwiftUI's `.shadow` lowers to a CALayer `shadowOffset` that the
/// offscreen `NSHostingView.cacheDisplay` path (export / Preview) renders with its
/// **global** Y mirrored versus live on-screen compositing (editor) — so the shadow sits
/// below the device live but above it in export. (We use `.shadow` rather than a
/// `.blur`-based silhouette because `.blur` under-renders offscreen, which would make the
/// editor and export blur differ; `.shadow`'s blur is identical in both paths.)
///
/// The shadow's offset is applied in the device's local (pre-rotation) space, but the
/// flip is global, so for a rotated device a plain Y-negation points the shadow the wrong
/// way. We instead feed the export path the local offset `L = R(-θ)·F·R(θ)·(ox, oy)`
/// (F = vertical mirror), which after the global flip lands exactly where the editor
/// draws it, at any rotation. For θ = 0 this reduces to `(ox, -oy)`.
///
/// Shadow geometry is stored in model space and scaled by `displayScale` so the editor
/// (display scale) and export (scale 1.0) stay in parity — same precedent as
/// `displayOutlineWidth`.
struct DeviceShadowModifier: ViewModifier {
    let shadow: ShadowConfig?
    let displayScale: CGFloat
    /// The device's rotation in degrees — needed to compensate the offscreen flip when rotated.
    let rotationDegrees: Double
    @Environment(\.isExportRendering) private var isExportRendering

    func body(content: Content) -> some View {
        if let shadow, shadow.isActive {
            let ox = shadow.resolvedOffsetX * displayScale
            let oy = shadow.resolvedOffsetY * displayScale
            let offset = compensatedOffset(ox: ox, oy: oy)
            content
                .compositingGroup()
                .shadow(
                    color: shadow.resolvedColor.opacity(shadow.resolvedOpacity),
                    radius: shadow.resolvedRadius * displayScale,
                    x: offset.x,
                    y: offset.y
                )
        } else {
            content
        }
    }

    /// Live: the offset as-authored. Export: `R(-θ)·F·R(θ)·(ox,oy)`, which after the
    /// offscreen global vertical flip reproduces the live offset at any rotation.
    private func compensatedOffset(ox: CGFloat, oy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        guard isExportRendering else { return (ox, oy) }
        let t = 2 * rotationDegrees * .pi / 180
        let c = cos(t), s = sin(t)
        return (x: ox * c - oy * s, y: -(ox * s + oy * c))
    }
}
