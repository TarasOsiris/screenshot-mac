import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        if let rowIndex = state.selectedRowIndex {
            Form {
                Section("Row") {
                    TextField("Row label", text: $state.rows[rowIndex].label.onSet { state.scheduleSave() })
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($isLabelFocused)
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
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                            ForEach(gradientPresets) { preset in
                                let isSelected = state.rows[rowIndex].gradientConfig == preset.config

                                Button {
                                    state.rows[rowIndex].gradientConfig = preset.config
                                    state.scheduleSave()
                                } label: {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(preset.config.linearGradient)
                                        .frame(height: 28)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 4)
                                                .strokeBorder(isSelected ? Color.accentColor : .white.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(preset.label)
                            }
                        }

                        ColorPicker(
                            "Color 1",
                            selection: $state.rows[rowIndex].gradientConfig.color1.onSet { state.scheduleSave() },
                            supportsOpacity: false
                        )
                        .font(.system(size: 12))

                        ColorPicker(
                            "Color 2",
                            selection: $state.rows[rowIndex].gradientConfig.color2.onSet { state.scheduleSave() },
                            supportsOpacity: false
                        )
                        .font(.system(size: 12))

                        LabeledContent("Angle") {
                            HStack(spacing: 8) {
                                Slider(
                                    value: $state.rows[rowIndex].gradientConfig.angle.onSet { state.scheduleSave() },
                                    in: 0...360,
                                    step: 1
                                )
                                .controlSize(.small)
                                Text("\(Int(state.rows[rowIndex].gradientConfig.angle))°")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, alignment: .trailing)
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

    private func parseSizeTag(_ tag: String) -> (width: CGFloat, height: CGFloat)? {
        parseSizeString(tag)
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
                guard let size = parseSizeTag(newValue) else { return }
                state.rows[rowIndex].templateWidth = size.width
                state.rows[rowIndex].templateHeight = size.height
                state.scheduleSave()
            }
        )
    }
}
