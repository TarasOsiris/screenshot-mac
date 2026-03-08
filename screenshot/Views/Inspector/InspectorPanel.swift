import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        if let rowIndex = state.selectedRowIndex {
            Form {
                Section("Row") {
                    TextField("Row label", text: $state.rows[rowIndex].label.limited(to: 50).onSet { state.scheduleSave() }, prompt: Text("Row label"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .labelsHidden()
                        .focused($isLabelFocused)
                        .onSubmit { isLabelFocused = false }
                }

                Section("Screenshot Size") {
                    Picker("Preset", selection: sizePresetBinding(for: rowIndex)) {
                        ForEach(displayCategories) { category in
                            Section(category.name) {
                                ForEach(category.sizes, id: \.label) { size in
                                    Text("\(size.label) \(size.isLandscape ? "Landscape" : "Portrait")")
                                        .tag(sizePresetTag(for: size))
                                }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)

                    LabeledContent("Size") {
                        Text(verbatim: state.rows[rowIndex].resolutionLabel)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Background") {
                    Picker("Style", selection: $state.rows[rowIndex].backgroundStyle.onSet { state.scheduleSave() }) {
                        Text("Color").tag(BackgroundStyle.color)
                        Text("Gradient").tag(BackgroundStyle.gradient)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)

                    if state.rows[rowIndex].backgroundStyle == .color {
                        ColorPicker(
                            "Color",
                            selection: $state.rows[rowIndex].bgColor.onSet { state.scheduleSave() },
                            supportsOpacity: false
                        )
                        .font(.system(size: 12))
                    } else {
                        // Gradient stop editor (preview bar + stop handles + color picker)
                        GradientStopEditor(
                            config: $state.rows[rowIndex].gradientConfig,
                            onChanged: { state.scheduleSave() }
                        )

                        // Preset grid
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(gradientPresets) { preset in
                                Button {
                                    state.rows[rowIndex].gradientConfig = preset.config
                                    state.scheduleSave()
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(preset.config.linearGradient)
                                        .frame(height: 28)
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

                        // Angle: wheel + value + quick presets
                        VStack(spacing: 6) {
                            HStack(spacing: 12) {
                                GradientAngleWheel(
                                    angle: $state.rows[rowIndex].gradientConfig.angle.onSet { state.scheduleSave() }
                                )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(Int(state.rows[rowIndex].gradientConfig.angle))°")
                                        .font(.system(size: 18, weight: .medium).monospacedDigit())
                                        .foregroundStyle(.primary)

                                    // Quick angle buttons
                                    HStack(spacing: 2) {
                                        ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { a in
                                            Button {
                                                state.rows[rowIndex].gradientConfig.angle = Double(a)
                                                state.scheduleSave()
                                            } label: {
                                                Image(systemName: "arrow.up")
                                                    .font(.system(size: 8))
                                                    .rotationEffect(.degrees(Double(a)))
                                                    .frame(width: 18, height: 18)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(Int(state.rows[rowIndex].gradientConfig.angle) == a ? Color.accentColor.opacity(0.3) : Color.clear)
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
                }

                Section("Elements") {
                    ShapeToolbar(state: state)
                }

                Section("Options") {
                    Toggle("Show devices", isOn: $state.rows[rowIndex].showDevice.onSet { state.scheduleSave() })
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                    Toggle("Show borders", isOn: $state.rows[rowIndex].showBorders.onSet { state.scheduleSave() })
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .formStyle(.grouped)
            .onAppear { isLabelFocused = false }
            .onChange(of: state.selectedRowId) { isLabelFocused = false }
            .onChange(of: state.selectedShapeId) { if state.selectedShapeId != nil { isLabelFocused = false } }
        } else {
            ContentUnavailableView(
                "No Row Selected",
                systemImage: "rectangle.stack",
                description: Text("Select a row to edit its settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func sizePresetTag(for size: ScreenshotSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    private func sizePresetBinding(for rowIndex: Int) -> Binding<String> {
        Binding(
            get: {
                sizePresetTag(for: ScreenshotSize(
                    width: state.rows[rowIndex].templateWidth,
                    height: state.rows[rowIndex].templateHeight
                ))
            },
            set: { newValue in
                guard let size = parseSizeString(newValue) else { return }
                state.rows[rowIndex].templateWidth = size.width
                state.rows[rowIndex].templateHeight = size.height
                state.scheduleSave()
            }
        )
    }
}
