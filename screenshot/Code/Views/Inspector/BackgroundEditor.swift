import SwiftUI
import UniformTypeIdentifiers

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

    var body: some View {
        Picker("Style", selection: $backgroundStyle.onSet { onChanged() }) {
            Text("Color").tag(BackgroundStyle.color)
            Text("Gradient").tag(BackgroundStyle.gradient)
            Text("Image").tag(BackgroundStyle.image)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .controlSize(.mini)

        switch backgroundStyle {
        case .color:
            HStack {
                Text("Color")
                Spacer()
                ColorPicker("", selection: $bgColor.onSet { onChanged() }, supportsOpacity: false)
                    .labelsHidden()
                    .fixedSize()
            }
            .font(.system(size: 10))

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
                .controlSize(.mini)

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
                            RoundedRectangle(cornerRadius: 4)
                                .fill(preset.config.linearGradient)
                                .frame(height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                )
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
        HStack(alignment: .top, spacing: 8) {
            GradientAngleWheel(
                angle: $gradientConfig.angle.onSet { onChanged() }
            )
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(gradientConfig.angle))°")
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.primary)

                HStack(spacing: 1) {
                    ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { a in
                        Button {
                            gradientConfig.angle = Double(a)
                            onChanged()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 7))
                                .rotationEffect(.degrees(Double(a)))
                                .frame(width: 14, height: 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Int(gradientConfig.angle.rounded()) == a ? Color.accentColor.opacity(0.3) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("\(a)°")
                    }
                }
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 6)
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
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Text("X: \(Int(gradientConfig.centerX * 100))%")
                    Text("Y: \(Int(gradientConfig.centerY * 100))%")
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.primary)

                Button {
                    gradientConfig.centerX = 0.5
                    gradientConfig.centerY = 0.5
                    onChanged()
                } label: {
                    Text("Reset")
                        .font(.system(size: 9))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .opacity(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5 ? 0.3 : 1)
                .disabled(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5)
            }
        }
        .padding(.leading, 4)
    }
}

struct BackgroundImageEditor: View {
    @Binding var config: BackgroundImageConfig
    let image: NSImage?
    var onChanged: () -> Void
    var onPickImage: () -> Void
    var onRemoveImage: () -> Void
    var onDropImage: ((NSImage) -> Void)?
    var onDropSvg: ((String) -> Void)?
    @State private var isDropTargeted = false
    @State private var cachedSvgPreview: NSImage?

    private var hasImage: Bool { config.hasImage || image != nil }

    private var previewImage: NSImage? { image ?? cachedSvgPreview }

    var body: some View {
        Group {
            if let preview = previewImage {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(
                                isDropTargeted ? Color.accentColor.opacity(0.75) : Color.secondary.opacity(0.3),
                                style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1)
                            )
                    )

                HStack(spacing: 4) {
                    Button("Replace") { onPickImage() }
                        .controlSize(.small)
                    Button("Remove", role: .destructive) { onRemoveImage() }
                        .controlSize(.small)
                }
                .font(.system(size: 10))
            } else {
                Button {
                    onPickImage()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                            .font(.system(size: 16))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                        Text(isDropTargeted ? "Drop Image" : "Choose or Drop Image")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(
                                style: StrokeStyle(lineWidth: isDropTargeted ? 1.5 : 1, dash: [4, 4])
                            )
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .onDrop(of: [.image, .svg, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
        }
        .onAppear { updateSvgPreview() }
        .onChange(of: config.svgContent) { updateSvgPreview() }

        if !hasImage {
            Text("Drop or paste an image to configure fill and opacity.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }

        Picker("Fill", selection: $config.fillMode.onSet { onChanged() }) {
            Text("Fill").tag(ImageFillMode.fill)
            Text("Fit").tag(ImageFillMode.fit)
            Text("Stretch").tag(ImageFillMode.stretch)
            Text("Tile").tag(ImageFillMode.tile)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .controlSize(.mini)
        .disabled(!hasImage)

        sliderRow("Opacity", value: $config.opacity)

        if config.fillMode == .tile {
            VStack(spacing: 4) {
                axisSliderRow(
                    "Scale",
                    xValue: $config.tileScaleX,
                    yValue: $config.tileScaleY,
                    range: 0.1...3.0,
                    xFormat: { "\(String(format: "%.1f", config.tileScaleX))x" },
                    yFormat: { "\(String(format: "%.1f", config.tileScaleY))x" }
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
                .font(.system(size: 10))
            Spacer()
            Slider(value: value.onSet { onChanged() }, in: range)
                .frame(width: 80)
                .disabled(!hasImage)
            Text(formatLabel?() ?? "\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 9).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 38, alignment: .trailing)
        }
        .opacity(hasImage ? 1 : 0.45)
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
                .font(.system(size: 10))
            axisSlider("X", value: xValue, range: range, formatLabel: xFormat, valueWidth: 34)
            axisSlider("Y", value: yValue, range: range, formatLabel: yFormat, valueWidth: 34)
        }
        .opacity(hasImage ? 1 : 0.45)
    }

    private func axisSlider(
        _ axis: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        formatLabel: (() -> String)?,
        valueWidth: CGFloat
    ) -> some View {
        HStack(spacing: 4) {
            Text(axis)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 10)
            Slider(value: value.onSet { onChanged() }, in: range)
                .disabled(!hasImage)
            Text(formatLabel?() ?? "\(Int(value.wrappedValue * 100))%")
                .font(.system(size: 9).monospacedDigit())
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

        if provider.hasItemConformingToTypeIdentifier(UTType.svg.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.svg.identifier) { url, _ in
                guard let url, let sanitized = SvgHelper.loadAndSanitize(from: url) else { return }
                DispatchQueue.main.async { onDropSvg?(sanitized) }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { return }
                if let sanitized = SvgHelper.loadAndSanitize(from: url) {
                    DispatchQueue.main.async { onDropSvg?(sanitized) }
                } else if let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { onDropImage?(image) }
                }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                guard let url else { return }
                if let sanitized = SvgHelper.loadAndSanitize(from: url) {
                    DispatchQueue.main.async { onDropSvg?(sanitized) }
                } else if let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                          let type = UTType(typeId),
                          type.conforms(to: .image),
                          let image = NSImage(contentsOf: url) {
                    DispatchQueue.main.async { onDropImage?(image) }
                }
            }
            return true
        }

        return false
    }
}
