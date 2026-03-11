import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        if let rowIndex = state.selectedRowIndex {
            Form {
                Section("Row") {
                    TextField("Row label", text: $state.rows[rowIndex].label.limited(to: 50).onSet {
                        state.rows[rowIndex].isLabelManuallySet = true
                        state.scheduleSave()
                    }, prompt: Text("Row label"))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                        .labelsHidden()
                        .focused($isLabelFocused)
                        .onSubmit {
                            if state.rows[rowIndex].label.trimmingCharacters(in: .whitespaces).isEmpty {
                                let row = state.rows[rowIndex]
                                state.rows[rowIndex].label = presetLabel(forWidth: row.templateWidth, height: row.templateHeight)
                                state.rows[rowIndex].isLabelManuallySet = false
                                state.scheduleSave()
                            }
                            isLabelFocused = false
                        }
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
                    BackgroundEditor(
                        backgroundStyle: $state.rows[rowIndex].backgroundStyle,
                        bgColor: $state.rows[rowIndex].bgColor,
                        gradientConfig: $state.rows[rowIndex].gradientConfig,
                        backgroundImageConfig: $state.rows[rowIndex].backgroundImageConfig,
                        backgroundImage: state.rows[rowIndex].backgroundImageConfig.fileName.flatMap { state.screenshotImages[$0] },
                        onChanged: { state.scheduleSave() },
                        onPickImage: { state.pickAndSaveBackgroundImage(for: state.rows[rowIndex].id) },
                        onRemoveImage: { state.removeBackgroundImage(for: state.rows[rowIndex].id) },
                        onDropImage: { image in
                            state.saveBackgroundImage(image, for: state.rows[rowIndex].id)
                        }
                    )

                    if state.rows[rowIndex].backgroundStyle != .color {
                        let canSpanAcrossRow = state.rows[rowIndex].templates.count > 1
                        Toggle("Span across row", isOn: $state.rows[rowIndex].spanBackgroundAcrossRow.onSet { state.scheduleSave() })
                            .font(.system(size: 12))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!canSpanAcrossRow)
                            .help(spanAcrossRowHelp(for: rowIndex, canSpanAcrossRow: canSpanAcrossRow))

                        if !canSpanAcrossRow {
                            Text("Add at least two screenshots to span across row.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Elements") {
                    ShapeToolbar(state: state)
                }

                Section("Device") {
                    Picker("Default device", selection: $state.rows[rowIndex].defaultDeviceCategory.onSet { state.scheduleSave() }) {
                        ForEach(DeviceCategory.allCases, id: \.self) { cat in
                            Label(cat.label, systemImage: cat.icon).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .font(.system(size: 12))

                    LabeledContent("Default body color") {
                        ColorPicker("", selection: rowDefaultDeviceBodyColorBinding(for: rowIndex), supportsOpacity: false)
                            .labelsHidden()
                            .help("Default device body color for this row")
                    }
                    .font(.system(size: 12))
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
                state.resizeRow(at: rowIndex, newWidth: size.width, newHeight: size.height)
            }
        )
    }

    private func rowDefaultDeviceBodyColorBinding(for rowIndex: Int) -> Binding<Color> {
        Binding(
            get: { state.rows[rowIndex].defaultDeviceBodyColor },
            set: { state.updateRowDefaultDeviceBodyColor($0, for: state.rows[rowIndex].id) }
        )
    }

    private func spanAcrossRowHelp(for rowIndex: Int, canSpanAcrossRow: Bool) -> String {
        canSpanAcrossRow
            ? "Apply background across the entire row instead of repeating per screenshot"
            : "Requires at least two screenshots in the row"
    }
}
