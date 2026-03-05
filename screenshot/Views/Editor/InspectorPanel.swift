import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool

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

                    // Device preset
                    inspectorSection("Device") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(DeviceCategory.allCases) { category in
                                DisclosureGroup(category.rawValue) {
                                    ForEach(devicePresets.filter { $0.category == category }) { preset in
                                        let isSelected = row.templateWidth == preset.width && row.templateHeight == preset.height
                                        Button {
                                            state.rows[rowIndex].templateWidth = preset.width
                                            state.rows[rowIndex].templateHeight = preset.height
                                            state.scheduleSave()
                                        } label: {
                                            HStack {
                                                Image(systemName: category.icon)
                                                    .font(.system(size: 11))
                                                    .frame(width: 16)
                                                Text(preset.name)
                                                    .font(.system(size: 12))
                                                Spacer()
                                                Text(verbatim: "\(Int(preset.width))x\(Int(preset.height))")
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
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Background color
                    inspectorSection("Background") {
                        ColorPicker(
                            "Color",
                            selection: $state.rows[rowIndex].bgColor.onSet { state.scheduleSave() },
                            supportsOpacity: false
                        )
                        .font(.system(size: 12))
                    }

                    // Elements (add shapes)
                    inspectorSection("Elements") {
                        ShapeToolbar(state: state)
                    }

                    // Options
                    inspectorSection("Options") {
                        Toggle("Show device frame", isOn: $state.rows[rowIndex].showDevice.onSet { state.scheduleSave() })
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
