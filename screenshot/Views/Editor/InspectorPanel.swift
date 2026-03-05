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

                    Divider()

                    // Device preset
                    inspectorSection("Screenshot Size") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(displayCategories) { category in
                                DisclosureGroup(category.name) {
                                    ForEach(category.sizes) { size in
                                        let isSelected = row.templateWidth == size.width && row.templateHeight == size.height
                                        Button {
                                            state.rows[rowIndex].templateWidth = size.width
                                            state.rows[rowIndex].templateHeight = size.height
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
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    // Background color
                    inspectorSection("Background") {
                        ColorPicker(
                            "Color",
                            selection: $state.rows[rowIndex].bgColor.onSet { state.scheduleSave() },
                            supportsOpacity: false
                        )
                        .font(.system(size: 12))
                    }

                    Divider()

                    // Elements (add shapes)
                    inspectorSection("Elements") {
                        ShapeToolbar(state: state)
                    }

                    Divider()

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
