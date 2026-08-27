import SwiftUI
import UniformTypeIdentifiers

/// Desktop-dense fixed-point fonts on macOS; standard Dynamic Type styles on iPad.
private enum EditorFont {
    #if os(macOS)
    static let row = Font.system(size: UIMetrics.FontSize.body)
    static let label = Font.system(size: UIMetrics.FontSize.inlineLabel)
    static let value = Font.system(size: UIMetrics.FontSize.numericBadge).monospacedDigit()
    static let hint = Font.system(size: UIMetrics.FontSize.hint)
    static let axisValue = Font.system(size: UIMetrics.FontSize.hint).monospacedDigit()
    #else
    static let row = Font.body
    static let label = Font.subheadline
    static let value = Font.footnote.monospacedDigit()
    static let hint = Font.footnote
    static let axisValue = Font.footnote.monospacedDigit()
    #endif
}

#if os(macOS)
private let sliderValueColumnWidth: CGFloat = 38
private let axisValueColumnWidth: CGFloat = 34
private let axisLabelWidth: CGFloat = 10
#else
private let sliderValueColumnWidth: CGFloat = 48
private let axisValueColumnWidth: CGFloat = 44
private let axisLabelWidth: CGFloat = 14
#endif

struct BackgroundEditor: View {
    @Binding var backgroundStyle: BackgroundStyle
    @Binding var bgColor: Color
    @Binding var gradientConfig: GradientConfig
    @Binding var backgroundImageConfig: BackgroundImageConfig
    var backgroundImage: NSImage?
    var onChanged: () -> Void
    var onPickImage: (() -> Void)?
    var onRemoveImage: (() -> Void)?
    var onDropImage: ((NSImage) -> Void)?
    var onDropSvg: ((String) -> Void)?

    #if os(macOS)
    private static let gradientPresetTileHeight: CGFloat = 24
    #else
    private static let gradientPresetTileHeight: CGFloat = 40
    #endif

    var body: some View {
        Picker("Style", selection: $backgroundStyle.onSet { onChanged() }) {
            Text("Color").tag(BackgroundStyle.color)
            Text("Gradient").tag(BackgroundStyle.gradient)
            Text("Image").tag(BackgroundStyle.image)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .iPadTappableSegmentedControl()

        switch backgroundStyle {
        case .color:
            HStack {
                Text("Color")
                Spacer()
                ColorPicker("", selection: $bgColor.onSet { onChanged() }, supportsOpacity: false)
                    .labelsHidden()
                    .iPadColorSwatchFrame()
                    .fixedSize()
            }
            .font(EditorFont.row)

        case .gradient:
            VStack(alignment: .leading, spacing: 10) {
                Picker("Type", selection: $gradientConfig.gradientType.onSet { onChanged() }) {
                    Text("Linear").tag(GradientType.linear)
                    Text("Radial").tag(GradientType.radial)
                    Text("Angular").tag(GradientType.angular)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .iPadTappableSegmentedControl()

                GradientStopEditor(
                    config: $gradientConfig,
                    onChanged: onChanged
                )

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(gradientPresets) { preset in
                        Button {
                            var presetConfig = preset.config
                            presetConfig.gradientType = gradientConfig.gradientType
                            presetConfig.centerX = gradientConfig.centerX
                            presetConfig.centerY = gradientConfig.centerY
                            gradientConfig = presetConfig
                            onChanged()
                        } label: {
                            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                                .fill(preset.config.linearGradient)
                                .frame(height: Self.gradientPresetTileHeight)
                                .overlay {
                                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                                        .strokeBorder(UIMetrics.Stroke.subtle, lineWidth: UIMetrics.BorderWidth.standard)
                                }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(preset.label)
                    }
                }

                switch gradientConfig.gradientType {
                case .linear:
                    angleControls

                case .radial, .angular:
                    centerControls

                    if gradientConfig.gradientType == .angular {
                        angleControls
                    }
                }
            }

        case .image:
            BackgroundImageEditor(
                config: $backgroundImageConfig,
                image: backgroundImage,
                onChanged: onChanged,
                onPickImage: onPickImage ?? {},
                onRemoveImage: onRemoveImage ?? {},
                onDropImage: onDropImage,
                onDropSvg: onDropSvg
            )
        }
    }

    @ViewBuilder
    private var angleControls: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .center, spacing: 2) {
                GradientAngleWheel(
                    angle: $gradientConfig.angle.onSet { onChanged() }
                )
                .frame(width: UIMetrics.GradientEditor.angleWheelSize, height: UIMetrics.GradientEditor.angleWheelSize)

                Text("\(Int(gradientConfig.angle))°")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(width: UIMetrics.GradientEditor.angleWheelSize)
            }

            anglePresetButtons
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var anglePresetButtons: some View {
        let angles = [0, 45, 90, 135, 180, 225, 270, 315]
        #if os(macOS)
        HStack(spacing: 1) {
            ForEach(angles, id: \.self) { anglePresetButton($0) }
        }
        #else
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(UIMetrics.GradientEditor.anglePresetButtonWidth), spacing: 4), count: 4), spacing: 4) {
            ForEach(angles, id: \.self) { anglePresetButton($0) }
        }
        #endif
    }

    private func anglePresetButton(_ a: Int) -> some View {
        Button {
            gradientConfig.angle = Double(a)
            onChanged()
        } label: {
            Image(systemName: "arrow.up")
                .font(.system(size: UIMetrics.GradientEditor.anglePresetGlyphSize))
                .rotationEffect(.degrees(Double(a)))
                .frame(
                    width: UIMetrics.GradientEditor.anglePresetButtonWidth,
                    height: UIMetrics.GradientEditor.anglePresetButtonHeight
                )
                .background(
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                        .fill(Int(gradientConfig.angle.rounded()) == a ? Color.accentColor.opacity(UIMetrics.Opacity.accentSelection) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip))
        }
        .buttonStyle(.plain)
        // Degrees are notation, not prose — same rationale as the X/Y/W/H field labels.
        .accessibilityLabel(Text(verbatim: "\(a)°"))
        .focusable(false)
        .help("\(a)°")
    }

    @ViewBuilder
    private var centerControls: some View {
        HStack(alignment: .top, spacing: 8) {
            GradientCenterPicker(
                centerX: $gradientConfig.centerX.onSet { onChanged() },
                centerY: $gradientConfig.centerY.onSet { onChanged() }
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Center")
                    .font(EditorFont.label)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("X: \(Int(gradientConfig.centerX * 100))%")
                    Text("Y: \(Int(gradientConfig.centerY * 100))%")
                }
                .font(EditorFont.value)
                .foregroundStyle(.primary)

                Button {
                    gradientConfig.centerX = 0.5
                    gradientConfig.centerY = 0.5
                    onChanged()
                } label: {
                    Text("Reset")
                        .font(EditorFont.hint)
                        .iPadResetTapTarget()
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .opacity(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5 ? UIMetrics.Opacity.disabled : 1)
                .disabled(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5)
            }
        }
        .padding(.leading, 4)
    }
}

struct BackgroundImageEditor: View {
    @Environment(\.reportDropFailure) private var reportDropFailure
    @Binding var config: BackgroundImageConfig
    let image: NSImage?
    var onChanged: () -> Void
    var onPickImage: () -> Void
    var onRemoveImage: () -> Void
    var onDropImage: ((NSImage) -> Void)?
    var onDropSvg: ((String) -> Void)?
    @State private var isDropTargeted = false
    @State private var cachedSvgPreview: NSImage?
    #if os(iOS)
    @State private var showImagePicker = false
    #endif

    private var hasImage: Bool { config.hasImage || image != nil }

    private var previewImage: NSImage? { image ?? cachedSvgPreview }

    private func previewThumbnail(_ preview: NSImage) -> some View {
        Image(nsImage: preview)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxHeight: 60)
            .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip))
            .overlay {
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                    .strokeBorder(
                        isDropTargeted ? Color.accentColor.opacity(UIMetrics.Opacity.accentEmphasis) : Color.secondary.opacity(UIMetrics.Opacity.accentSelection),
                        style: StrokeStyle(lineWidth: isDropTargeted ? UIMetrics.BorderWidth.emphasis : UIMetrics.BorderWidth.standard)
                    )
            }
    }

    private var dropZoneLabel: some View {
        VStack(spacing: 4) {
            Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 16))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
            Text(isDropTargeted ? "Drop Image" : "Choose or Drop Image")
                .scaledFont(UIMetrics.FontSize.inlineLabel)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.card)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: isDropTargeted ? UIMetrics.BorderWidth.emphasis : UIMetrics.BorderWidth.standard, dash: [4, 4])
                )
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        )
    }

    var body: some View {
        Group {
            if let preview = previewImage {
                #if os(macOS)
                previewThumbnail(preview)

                HStack(spacing: 4) {
                    Button("Replace") { onPickImage() }
                        .controlSize(.small)
                    Button("Remove", role: .destructive) { onRemoveImage() }
                        .controlSize(.small)
                }
                .scaledFont(UIMetrics.FontSize.inlineLabel)
                #else
                HStack(spacing: 12) {
                    previewThumbnail(preview)

                    Spacer(minLength: 0)

                    Button {
                        showImagePicker = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .imageSourcePicker(isPresented: $showImagePicker) { onDropImage?($0) }
                    .accessibilityLabel("Replace Image")

                    Button(role: .destructive) {
                        onRemoveImage()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(.red)
                    .accessibilityLabel("Remove Image")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                #endif
            } else {
                #if os(macOS)
                Button {
                    onPickImage()
                } label: {
                    dropZoneLabel
                }
                .buttonStyle(.plain)
                #else
                Button {
                    showImagePicker = true
                } label: {
                    Label("Add Image", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .imageSourcePicker(isPresented: $showImagePicker) { onDropImage?($0) }
                #endif
            }
        }
        .onDrop(of: [.image, .svg, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
        }
        .onAppear { updateSvgPreview() }
        .onChange(of: config.svgContent) { updateSvgPreview() }

        #if os(macOS)
        if !hasImage {
            Text("Drop or paste an image to configure fill and opacity.")
                .scaledFont(UIMetrics.FontSize.hint)
                .foregroundStyle(.secondary)
        }
        #endif

        Picker("Fill", selection: $config.fillMode.onSet { onChanged() }) {
            Text("Fill").tag(ImageFillMode.fill)
            Text("Fit").tag(ImageFillMode.fit)
            Text("Stretch").tag(ImageFillMode.stretch)
            Text("Tile").tag(ImageFillMode.tile)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .iPadTappableSegmentedControl()
        .disabled(!hasImage)

        sliderRow("Opacity", value: $config.opacity)

        if config.fillMode == .tile {
            VStack(spacing: 4) {
                axisSliderRow(
                    "Scale",
                    xValue: $config.tileScaleX,
                    yValue: $config.tileScaleY,
                    range: 0.1...3.0,
                    xFormat: { "\(config.tileScaleX.formatted(.number.precision(.fractionLength(1))))x" },
                    yFormat: { "\(config.tileScaleY.formatted(.number.precision(.fractionLength(1))))x" }
                )
                axisSliderRow("Spacing", xValue: $config.tileSpacingX, yValue: $config.tileSpacingY)
                axisSliderRow("Offset", xValue: $config.tileOffsetX, yValue: $config.tileOffsetY)
            }
        }
    }

    private func sliderRow(
        _ label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1.0,
        formatLabel: (() -> String)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(EditorFont.label)
            #if os(macOS)
            Spacer()
            Slider(value: value.onSet { onChanged() }, in: range)
                .frame(width: UIMetrics.SliderWidth.standard)
                .disabled(!hasImage)
            #else
            Slider(value: value.onSet { onChanged() }, in: range)
                .disabled(!hasImage)
                .padding(.horizontal, 4)
            #endif
            Text(formatLabel?() ?? "\(Int(value.wrappedValue * 100))%")
                .font(EditorFont.value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: sliderValueColumnWidth, alignment: .trailing)
        }
        .opacity(hasImage ? 1 : UIMetrics.Opacity.disabled)
    }

    private func axisSliderRow(
        _ label: LocalizedStringKey,
        xValue: Binding<Double>,
        yValue: Binding<Double>,
        range: ClosedRange<Double> = 0...1.0,
        xFormat: (() -> String)? = nil,
        yFormat: (() -> String)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(EditorFont.label)
            axisSlider("X", value: xValue, range: range, formatLabel: xFormat, valueWidth: axisValueColumnWidth)
            axisSlider("Y", value: yValue, range: range, formatLabel: yFormat, valueWidth: axisValueColumnWidth)
        }
        .opacity(hasImage ? 1 : UIMetrics.Opacity.disabled)
    }

    /// `axis` is notation, not prose — the catalog's single-letter keys machine-translate to
    /// words ("Y" → "Oui"), so it stays a plain String rendered verbatim.
    private func axisSlider(
        _ axis: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formatLabel: (() -> String)?,
        valueWidth: CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: axis)
                .font(EditorFont.hint.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: axisLabelWidth)
            Slider(value: value.onSet { onChanged() }, in: range)
                .disabled(!hasImage)
            Text(formatLabel?() ?? "\(Int(value.wrappedValue * 100))%")
                .font(EditorFont.axisValue)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: valueWidth, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }

    private func updateSvgPreview() {
        guard image == nil, let svg = config.svgContent else {
            cachedSvgPreview = nil
            return
        }
        let naturalSize = SvgHelper.parseViewBoxSize(svg) ?? CGSize(width: 100, height: 100)
        let maxDim: CGFloat = 120
        let scale = maxDim / max(naturalSize.width, naturalSize.height, 1)
        let targetSize = CGSize(width: ceil(naturalSize.width * scale), height: ceil(naturalSize.height * scale))
        cachedSvgPreview = SvgHelper.renderImage(from: svg, useColor: false, color: .white, targetSize: targetSize)
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard onDropImage != nil || onDropSvg != nil, let provider = providers.first else { return false }

        let candidates: [UTType] = [.svg, .image, .fileURL]
        guard let type = candidates.first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) else {
            return false
        }
        // `.fileURL` is the catch-all branch, so it has to confirm the file really is an image;
        // the other two identifiers already promise it.
        let mustConfirmImageType = (type == .fileURL)

        // Explicitly @Sendable: NSItemProvider calls this off the main queue, and under this
        // target's default-MainActor isolation a bare closure literal would be inferred
        // main-isolated and run on the wrong executor. It only decodes and hops back.
        let report = reportDropFailure
        provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { @Sendable url, error in
            let decoded = url.flatMap { DroppedFile.decode(at: $0, confirmingImageType: mustConfirmImageType) }
            let failure = decoded == nil ? DropFailure.imageOrSvg(error) : nil
            Task { @MainActor in
                switch decoded {
                case .svg(let content):
                    onDropSvg?(content)
                case .image(let image):
                    onDropImage?(image)
                case nil:
                    if let failure { report(failure) }
                }
            }
        }
        return true
    }
}

/// What a dropped file turned out to be. Decoded inside the item provider's completion
/// handler because the temporary URL it hands over is deleted as soon as that returns.
private enum DroppedFile {
    case svg(String)
    case image(NSImage)

    nonisolated static func decode(at url: URL, confirmingImageType: Bool) -> DroppedFile? {
        if let sanitized = SvgHelper.loadAndSanitize(from: url) { return .svg(sanitized) }
        if confirmingImageType {
            guard let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                  let type = UTType(typeId),
                  type.conforms(to: .image) else { return nil }
        }
        return NSImage(contentsOf: url).map(DroppedFile.image)
    }
}
