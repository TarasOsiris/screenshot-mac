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
                    BackgroundEditor(
                        backgroundStyle: $state.rows[rowIndex].backgroundStyle,
                        bgColor: $state.rows[rowIndex].bgColor,
                        gradientConfig: $state.rows[rowIndex].gradientConfig,
                        onChanged: { state.scheduleSave() }
                    )
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
