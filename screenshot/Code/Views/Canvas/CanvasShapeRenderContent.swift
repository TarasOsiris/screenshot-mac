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
    var screenshotImageIdentity: String?
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

        // One raster for the editor, preview and export alike. The editor used to host a live
        // `TextLayoutNSView` per text shape; those NSViews joined AppKit's `_layoutViewTree`, the
        // constraint pass and every hit test, which a scroll trace showed costing ~18% of the main
        // thread on a 111-shape project. The only live text view left is the one being edited.
        return RasterizedDisplayTextView(
            size: CGSize(width: effectiveW, height: effectiveH),
            text: displayText,
            font: nsFont,
            color: nsColor,
            alignment: align,
            verticalAlignment: verticalAlign,
            uppercase: uppercase,
            letterSpacing: shape.letterSpacing,
            lineHeightMultiple: shape.lineHeightMultiple,
            legacyLineSpacing: shape.lineSpacing,
            richTextData: richText,
            renderScale: textRenderScale
        )
        .frame(width: effectiveW, height: effectiveH)
        .background { textBackgroundLayer }
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
    }

    /// Extra resolution for the editor only. Preview and export draw at model scale using the
    /// historical platform default, so changing that factor would move exported bytes. The editor
    /// instead scales the raster by `displayScale` — a downscale for a tall App Store template, but
    /// an *upscale* on a short one at high zoom, which is what this covers.
    private var textRenderScale: CGFloat {
        guard showsEditorHelpers else { return TextLayoutStyle.defaultTextRenderScale }
        return TextLayoutStyle.quantizedTextRenderScale(displayScale * max(screenScale, 1))
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

            Group {
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
            .opacity(shape.textBackgroundOpacity ?? 1.0)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        let clip = RoundedRectangle(cornerRadius: shape.borderRadius * displayScale)
        withImageDropAffordances(
            ZStack {
                if let screenshotImage {
                    Image(nsImage: screenshotImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .clipShape(clip)
                } else {
                    clip.fill(Color.gray.opacity(0.3))
                }
            }
            .overlay { imageOutline(clip) }
        )
    }

    /// Border drawn inside the image's rounded-rect bounds — same "band from the edge inward"
    /// behavior as `outlinedShape`, so an image outline matches a rectangle outline in parity.
    @ViewBuilder
    private func imageOutline<S: InsettableShape>(_ clip: S) -> some View {
        let maxInset = max(0, min(displayW, displayH) / 2)
        let inset = min(displayOutlineWidth, maxInset)
        if let outlineColor = shape.outlineColor, inset > 0 {
            clip.strokeBorder(outlineColor, lineWidth: inset)
        }
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

        withImageDropAffordances(frame)
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

    /// Makes `base` an image drop target and puts the "add image" button and drop highlight over it.
    ///
    /// Everything editor-only is an overlay or a modifier, never a branch, so `base` holds one
    /// structural position for the shape's whole lifetime. A branch here re-keys whatever `base`
    /// renders — the hazard `CanvasShapeView` states one layer up: it cost a 3D device its cached
    /// raster (and therefore its pose) the moment a picked image arrived, and `showsEditorHelpers`
    /// would have done the same on every Edit↔Preview toggle, since that is a live toggle in one
    /// tree, not a per-host constant.
    private func withImageDropAffordances(_ base: some View) -> some View {
        let sizeRef = min(displayW, displayH)
        let cornerRadius = min(8, max(4, sizeRef * 0.04))

        return base
            .frame(width: displayW, height: displayH)
            .overlay {
                if showsEditorHelpers, screenshotImage == nil {
                    imagePickerButton(iconSize: min(28, max(14, sizeRef * 0.18)),
                                      padding: min(12, max(4, sizeRef * 0.05)),
                                      cornerRadius: cornerRadius)
                }
                if showsEditorHelpers, isDropTargeted {
                    dropHighlight(cornerRadius: cornerRadius)
                }
            }
            .onDrop(of: [.image], isTargeted: $isDropTargeted) { providers in
                guard showsEditorHelpers else { return false }
                return onHandleDrop(providers)
            }
    }

    private func imagePickerButton(iconSize: CGFloat, padding: CGFloat, cornerRadius: CGFloat) -> some View {
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
        .accessibilityLabel("Add Image")
        .help("Add Image")
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    @ViewBuilder
    private func dropHighlight(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Color.accentColor, lineWidth: max(2, 2 * displayScale))
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

/// True while a view is being rasterized offscreen (`RowRenderer.renderViewToImage`)
/// rather than composited live on screen. Used to compensate for AppKit's flipped-view
/// shadow handling. Defaults to false (live rendering).
extension EnvironmentValues {
    @Entry var isExportRendering = false
}

/// Applies a shape's configurable drop shadow.
///
/// `.compositingGroup()` flattens the shape's sub-layers (e.g. a device frame's screenshot +
/// bezel, or an image's clipped content) into one image first, so exactly one drop shadow is
/// cast from the unified silhouette — strictly behind the whole shape. Without it, SwiftUI casts
/// a shadow per sub-layer and an inner layer's offset shadow can bleed *inside* the shape.
///
/// Offscreen flip: SwiftUI's `.shadow` lowers to a CALayer `shadowOffset` that the
/// offscreen `NSHostingView.cacheDisplay` path (export / Preview) renders with its
/// **global** Y mirrored versus live on-screen compositing (editor) — so the shadow sits
/// below the device live but above it in export. (We use `.shadow` rather than a
/// `.blur`-based silhouette because `.blur` under-renders offscreen, which would make the
/// editor and export blur differ; `.shadow`'s blur is identical in both paths.)
///
/// The shadow's offset is applied in the shape's local (pre-rotation) space, but the
/// flip is global, so for a rotated shape a plain Y-negation points the shadow the wrong
/// way. We instead feed the export path the local offset `L = R(-θ)·F·R(θ)·(ox, oy)`
/// (F = vertical mirror), which after the global flip lands exactly where the editor
/// draws it, at any rotation. For θ = 0 this reduces to `(ox, -oy)`.
///
/// Shadow geometry is stored in model space and scaled by `displayScale` so the editor
/// (display scale) and export (scale 1.0) stay in parity — same precedent as
/// `displayOutlineWidth`.
struct ShadowModifier: ViewModifier {
    let shadow: ShadowConfig?
    let displayScale: CGFloat
    /// The shape's rotation in degrees — needed to compensate the offscreen flip when rotated.
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
    /// macOS-only: the flip is an `NSHostingView.cacheDisplay` artifact — iOS exports render
    /// through `ImageRenderer`, which does not flip (verified by pixel probe on the simulator),
    /// so compensating there would point every shadow the wrong way.
    private func compensatedOffset(ox: CGFloat, oy: CGFloat) -> (x: CGFloat, y: CGFloat) {
        #if os(macOS)
        guard isExportRendering else { return (ox, oy) }
        let t = 2 * rotationDegrees * .pi / 180
        let c = cos(t), s = sin(t)
        return (x: ox * c - oy * s, y: -(ox * s + oy * c))
        #else
        return (ox, oy)
        #endif
    }
}

/// A fixed non-rotated `.shadow(y:)` with the same offscreen-flip compensation as
/// `ShadowModifier` — for the built-in ambient shadows (showcase tiles, abstract device
/// bodies), which would otherwise point up in exports and down in the editor.
/// macOS-only for the same reason as `compensatedOffset`.
private struct FlipCompensatedShadow: ViewModifier {
    let color: Color
    let radius: CGFloat
    let y: CGFloat
    @Environment(\.isExportRendering) private var isExportRendering

    private var compensatedY: CGFloat {
        #if os(macOS)
        return isExportRendering ? -y : y
        #else
        return y
        #endif
    }

    func body(content: Content) -> some View {
        content.shadow(color: color, radius: radius, x: 0, y: compensatedY)
    }
}

extension View {
    func flipCompensatedShadow(color: Color, radius: CGFloat, y: CGFloat) -> some View {
        modifier(FlipCompensatedShadow(color: color, radius: radius, y: y))
    }
}
