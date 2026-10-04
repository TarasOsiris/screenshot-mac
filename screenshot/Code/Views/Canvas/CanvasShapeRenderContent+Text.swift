import SwiftUI

extension CanvasShapeRenderContent {
    var displayTextContent: some View {
        let rawText = shape.text ?? ""
        let showPlaceholder = showsEditorHelpers && rawText.isEmpty && !shape.hasRichText
        let nsFont = resolvedTextFont(italic: showPlaceholder ? true : (shape.italic ?? false))
        let displayText = showPlaceholder ? "Text" : rawText
        let nsColor = NSColor(shape.color.opacity(showPlaceholder ? 0.4 : 1.0))
        let align = shape.textAlign.nsTextAlignment
        let verticalAlign = shape.textVerticalAlign ?? .center
        let uppercase = shape.uppercase ?? false
        let richText = showPlaceholder ? nil : shape.richText
        var textInput = fitInput(font: nsFont)
        textInput.text = displayText
        textInput.richTextData = richText
        let shrinksToFit = shape.shrinkToFit == true && !showPlaceholder
        let isLive = isLiveTextLayout
        let fontScale = shrinksToFit ? TextFitMeasurer.fitScale(textInput, cachesResult: !isLive) : 1
        let showsOverflow = showsEditorHelpers && !showPlaceholder && !isLive
            && TextFitMeasurer.overflows(textInput, shrinksToFit: shrinksToFit)

        let stroke = showPlaceholder ? nil : textStroke
        func raster(glyphFill: TextGlyphFill?, stroke: TextStroke?) -> RasterizedDisplayTextView {
            RasterizedDisplayTextView(
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
                fontScale: fontScale,
                stroke: stroke,
                glyphFill: glyphFill,
                renderScale: textRenderScale,
                cachesRaster: !isLive
            )
        }

        // One raster for the editor, preview and export alike. The editor used to host a live
        // `TextLayoutNSView` per text shape; those NSViews joined AppKit's `_layoutViewTree`, the
        // constraint pass and every hit test, which a scroll trace showed costing ~18% of the main
        // thread on a 111-shape project. The only live text view left is the one being edited.
        return ZStack(alignment: .topLeading) {
            if shape.resolvedFillStyle == .gradient && !showPlaceholder {
                // Highlights and the outline, with no glyph fill, so the gradient shows through the
                // glyphs only. Plain text has neither, and would rasterize an empty layer.
                if stroke != nil || shape.hasRichText {
                    raster(glyphFill: .clear, stroke: stroke)
                }
                shape.fillView(image: nil, modelSize: CGSize(width: effectiveW, height: effectiveH))
                    .frame(width: effectiveW, height: effectiveH)
                    .mask { raster(glyphFill: .mask, stroke: nil) }
            } else {
                raster(glyphFill: nil, stroke: stroke)
            }
        }
        .frame(width: effectiveW, height: effectiveH)
        .background { textBackgroundLayer }
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: displayW, height: displayH, alignment: .topLeading)
        .overlay {
            if showsOverflow {
                // The box the text overflows, so it's clear which edge is the limit.
                ZStack(alignment: .bottomTrailing) {
                    Rectangle()
                        .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .allowsHitTesting(false)
                    textOverflowBadge
                }
            }
        }
    }

    /// Editor-only: TextKit drops the lines that don't fit, so without this a long translation
    /// just loses its last line with no sign anything is wrong.
    private var textOverflowBadge: some View {
        // A plain "!" centers in a circle; the triangle glyph's optical center sits low.
        Image(systemName: "exclamationmark")
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: UIMetrics.CanvasHandle.overflowBadgeSize, height: UIMetrics.CanvasHandle.overflowBadgeSize)
            .background(Color.orange, in: Circle())
            // Straddles the bottom edge it overflows, inset past the bottom-right resize handle's
            // hit area — that handle is how you fix it.
            .offset(x: -(UIMetrics.CanvasHandle.resizeHitSize / 2 + 5), y: UIMetrics.CanvasHandle.overflowBadgeSize / 2)
            .accessibilityLabel(Text("Text doesn't fit"))
            .help(Text("Text doesn't fit in its box. Enlarge the box, shorten the text, or turn on Shrink to Fit."))
    }

    private var textStroke: TextStroke? {
        guard let color = shape.outlineColor, let width = shape.outlineWidth, width > 0 else { return nil }
        return TextStroke(color: NSColor(color), width: width)
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
    var textEditor: some View {
        let nsFont = resolvedTextFont(italic: shape.italic ?? false)

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

        // Shrink-to-fit edits the unscaled text in a proportionally larger box, then scales the
        // whole view down, so the fonts written back to the shape are never the shrunk ones.
        let fontScale = editorFontScale(font: nsFont)

        #if os(iOS)
        editor
            .frame(width: displayW / fontScale, height: displayH / fontScale, alignment: .topLeading)
            .scaleEffect(fontScale, anchor: .topLeading)
            .frame(width: displayW, height: displayH, alignment: .topLeading)
        #else
        editor
            .frame(width: effectiveW / fontScale, height: effectiveH / fontScale)
            .scaleEffect(fontScale, anchor: .topLeading)
            .frame(width: effectiveW, height: effectiveH, alignment: .topLeading)
            .background { textBackgroundLayer }
            .scaleEffect(displayScale, anchor: .topLeading)
            .frame(width: displayW, height: displayH, alignment: .topLeading)
        #endif
    }

    private func resolvedTextFont(italic: Bool) -> NSFont {
        let fontSize = shape.fontSize ?? CanvasShapeModel.defaultFontSize
        return resolveNSFont(fontSize, CSSFontWeight(css: shape.fontWeight ?? 700).platform, italic)
    }

    /// The scale of the committed text, held for the whole edit: re-fitting per keystroke would
    /// make the text jump under the caret.
    private func editorFontScale(font: NSFont) -> CGFloat {
        guard shape.shrinkToFit == true else { return 1 }
        return TextFitMeasurer.fitScale(fitInput(font: font))
    }

    /// The shape's text laid out in the box it currently occupies, which a resize drag moves away
    /// from the stored size.
    private func fitInput(font: NSFont) -> TextFitInput {
        var input = TextFitInput(shape: shape, font: font)
        input.size = CGSize(width: effectiveW, height: effectiveH)
        return input
    }
}
