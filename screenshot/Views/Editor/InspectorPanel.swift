import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool
    @State private var expandedCategories: Set<String> = []

    var body: some View {
        if let rowIndex = state.selectedRowIndex {
            let row = state.rows[rowIndex]

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Row label
                    inspectorSection("Label") {
                        TextField("Row label", text: $state.rows[rowIndex].label.onSet { state.scheduleSave() })
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .focused($isLabelFocused)
                    }

                    Divider()

                    // Device preset
                    inspectorSection("Screenshot Size") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(displayCategories) { category in
                                let isExpanded = expandedCategories.contains(category.name)

                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if isExpanded {
                                            expandedCategories.remove(category.name)
                                        } else {
                                            expandedCategories.insert(category.name)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 8, weight: .semibold))
                                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                        Text(category.name)
                                    }
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                if isExpanded {
                                    ForEach(category.sizes) { size in
                                        let isSelected = row.templateWidth == size.width && row.templateHeight == size.height
                                        Button {
                                            state.rows[rowIndex].templateWidth = size.width
                                            state.rows[rowIndex].templateHeight = size.height
                                            state.rows[rowIndex].label = "\(category.name) — \(size.label)"
                                            state.scheduleSave()
                                        } label: {
                                            HStack {
                                                Text(size.label)
                                                    .font(.system(size: 12))
                                                Spacer()
                                                Text(size.isLandscape ? "Landscape" : "Portrait")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.secondary)
                                            }
                                            .padding(.vertical, 4)
                                            .padding(.horizontal, 8)
                                            .background(
                                                isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 4)
                                            )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    // Background
                    inspectorSection("Background") {
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
                            // Gradient presets grid
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
                                    .help(preset.label)
                                }
                            }

                            // Custom gradient controls
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

                            HStack {
                                Text("Angle")
                                    .font(.system(size: 12))
                                Slider(
                                    value: $state.rows[rowIndex].gradientConfig.angle.onSet { state.scheduleSave() },
                                    in: 0...360,
                                    step: 1
                                )
                                .controlSize(.small)
                                Text("\(Int(state.rows[rowIndex].gradientConfig.angle))°")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }

                    Divider()

                    // Elements (add shapes)
                    inspectorSection("Elements") {
                        ShapeToolbar(state: state)
                    }

                    Divider()

                    // Options
                    inspectorSection("Options") {
                        Toggle("Show devices", isOn: $state.rows[rowIndex].showDevice.onSet { state.scheduleSave() })
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)

                        Toggle("Show borders", isOn: $state.rows[rowIndex].showBorders.onSet { state.scheduleSave() })
                        .font(.system(size: 12))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }

                    Spacer()
                }
                .padding(16)
            }
            .onAppear { isLabelFocused = false }
            .onChange(of: state.selectedRowId) { isLabelFocused = false }
            .onChange(of: state.selectedShapeId) { if state.selectedShapeId != nil { isLabelFocused = false } }
        }
    }

    private func inspectorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
    }
}
