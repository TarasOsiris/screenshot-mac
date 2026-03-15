import SwiftUI
import UniformTypeIdentifiers

struct BackgroundEditor: View {
    @Binding var backgroundStyle: BackgroundStyle
    @Binding var bgColor: Color
    @Binding var gradientConfig: GradientConfig
    @Binding var backgroundImageConfig: BackgroundImageConfig
    var backgroundImage: NSImage?
    var compact: Bool = false
    var onChanged: () -> Void
    var onPickImage: (() -> Void)?
    var onRemoveImage: (() -> Void)?
    var onDropImage: ((NSImage) -> Void)?

    var body: some View {
        Picker("Style", selection: $backgroundStyle.onSet { onChanged() }) {
            Text("Color").tag(BackgroundStyle.color)
            Text("Gradient").tag(BackgroundStyle.gradient)
            Text("Image").tag(BackgroundStyle.image)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .controlSize(compact ? .mini : .small)

        switch backgroundStyle {
        case .color:
            HStack {
                Text("Color")
                Spacer()
                ColorPicker("", selection: $bgColor.onSet { onChanged() }, supportsOpacity: false)
                    .labelsHidden()
                    .fixedSize()
            }
            .font(.system(size: compact ? 10 : 12))

        case .gradient:
            Picker("Type", selection: $gradientConfig.gradientType.onSet { onChanged() }) {
                Text("Linear").tag(GradientType.linear)
                Text("Radial").tag(GradientType.radial)
                Text("Angular").tag(GradientType.angular)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .controlSize(compact ? .mini : .small)

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
                            .frame(height: compact ? 24 : 28)
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

        case .image:
            BackgroundImageEditor(
                config: $backgroundImageConfig,
                image: backgroundImage,
                compact: compact,
                onChanged: onChanged,
                onPickImage: onPickImage ?? {},
                onRemoveImage: onRemoveImage ?? {},
                onDropImage: onDropImage
            )
        }
    }

    @ViewBuilder
    private var angleControls: some View {
        let angleFontSize: CGFloat = compact ? 14 : 18
        let buttonSize: CGFloat = compact ? 14 : 18
        let arrowSize: CGFloat = compact ? 7 : 8

        VStack(spacing: 6) {
            HStack(spacing: compact ? 8 : 12) {
                GradientAngleWheel(
                    angle: $gradientConfig.angle.onSet { onChanged() }
                )
                .frame(width: compact ? 36 : nil, height: compact ? 36 : nil)

                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    Text("\(Int(gradientConfig.angle))°")
                        .font(.system(size: angleFontSize, weight: .medium).monospacedDigit())
                        .foregroundStyle(.primary)

                    HStack(spacing: compact ? 1 : 2) {
                        ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { a in
                            Button {
                                gradientConfig.angle = Double(a)
                                onChanged()
                            } label: {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: arrowSize))
                                    .rotationEffect(.degrees(Double(a)))
                                    .frame(width: buttonSize, height: buttonSize)
                                    .background(
                                        RoundedRectangle(cornerRadius: compact ? 2 : 3)
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
        }
    }

    @ViewBuilder
    private var centerControls: some View {
        HStack(spacing: compact ? 8 : 12) {
            GradientCenterPicker(
                centerX: $gradientConfig.centerX.onSet { onChanged() },
                centerY: $gradientConfig.centerY.onSet { onChanged() }
            )

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text("Center")
                    .font(.system(size: compact ? 10 : 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: compact ? 4 : 8) {
                    Text("X: \(Int(gradientConfig.centerX * 100))%")
                    Text("Y: \(Int(gradientConfig.centerY * 100))%")
                }
                .font(.system(size: compact ? 10 : 11).monospacedDigit())
                .foregroundStyle(.primary)

                Button {
                    gradientConfig.centerX = 0.5
                    gradientConfig.centerY = 0.5
                    onChanged()
                } label: {
                    Text("Reset")
                        .font(.system(size: compact ? 9 : 10))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(.secondary)
                .opacity(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5 ? 0.3 : 1)
                .disabled(gradientConfig.centerX == 0.5 && gradientConfig.centerY == 0.5)
            }
        }
    }
}

struct BackgroundImageEditor: View {
    @Binding var config: BackgroundImageConfig
    let image: NSImage?
    var compact: Bool = false
    var onChanged: () -> Void
    var onPickImage: () -> Void
    var onRemoveImage: () -> Void
    var onDropImage: ((NSImage) -> Void)?
    @State private var isDropTargeted = false

    private var hasImage: Bool { image != nil }

    var body: some View {
        // Image preview / picker
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: compact ? 60 : 80)
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
                .font(.system(size: compact ? 10 : 11))
            } else {
                Button {
                    onPickImage()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "photo.on.rectangle.angled")
                            .font(.system(size: compact ? 16 : 20))
                            .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                        Text(isDropTargeted ? "Drop Image" : "Choose or Drop Image")
                            .font(.system(size: compact ? 10 : 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 44 : 56)
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
        .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleImageDrop(providers)
        }

        if !hasImage {
            Text("Add an image to enable fill and opacity controls.")
                .font(.system(size: compact ? 9 : 11))
                .foregroundStyle(.secondary)
        }

        // Fill mode
        Picker("Fill", selection: $config.fillMode.onSet { onChanged() }) {
            Text("Fill").tag(ImageFillMode.fill)
            Text("Fit").tag(ImageFillMode.fit)
            Text("Stretch").tag(ImageFillMode.stretch)
            Text("Tile").tag(ImageFillMode.tile)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .controlSize(compact ? .mini : .small)
        .disabled(!hasImage)

        sliderRow("Opacity", value: $config.opacity)

        if config.fillMode == .tile {
            sliderRow("Scale", value: $config.tileScale, range: 0.1...3.0) {
                "\(String(format: "%.1f", config.tileScale))x"
            }
            sliderRow("Spacing", value: $config.tileSpacing)
            sliderRow("Offset", value: $config.tileOffset)
        }
    }

    private func sliderRow(
        _ label: String,
        value: Binding<Double>,
        range: ClosedRange<Double> = 0...1.0,
        formatLabel: (() -> String)? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: compact ? 10 : 12))
            Spacer()
            Slider(value: value.onSet { onChanged() }, in: range)
                .frame(width: compact ? 80 : 100)
                .disabled(!hasImage)
            Text(formatLabel?() ?? "\(Int(value.wrappedValue * 100))%")
                .font(.system(size: compact ? 9 : 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: compact ? 38 : 34, alignment: .trailing)
        }
        .opacity(hasImage ? 1 : 0.45)
    }

    private func handleImageDrop(_ providers: [NSItemProvider]) -> Bool {
        guard onDropImage != nil, let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url, let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { onDropImage?(image) }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { url, _ in
                guard let url,
                      let typeId = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                      let type = UTType(typeId),
                      type.conforms(to: .image),
                      let image = NSImage(contentsOf: url) else { return }
                DispatchQueue.main.async { onDropImage?(image) }
            }
            return true
        }

        return false
    }
}
