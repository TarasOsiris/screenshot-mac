import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @FocusState private var isLabelFocused: Bool

    var body: some View {
        if let rowIndex = state.selectedRowIndex, let rowId = state.selectedRowId {
            Form {
                rowSection(rowId: rowId)
                sizeSection(rowIndex: rowIndex, rowId: rowId)
                backgroundSection(rowIndex: rowIndex, rowId: rowId)
                Section("Add new element") {
                    ShapeToolbar(state: state)
                }
                deviceSection(rowId: rowId)
                optionsSection(rowId: rowId)
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

    @ViewBuilder
    private func rowSection(rowId: UUID) -> some View {
        Section("Row") {
            TextField("Row label", text: safeRowBinding(rowId, keyPath: \.label, default: "").limited(to: 50).onSet {
                guard let ri = state.rowIndex(for: rowId) else { return }
                state.rows[ri].isLabelManuallySet = true
                state.scheduleSave()
            }, prompt: Text("Row label"))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .labelsHidden()
                .focused($isLabelFocused)
                .onSubmit {
                    state.updateRowLabel(rowId, text: state.rows[state.rowIndex(for: rowId) ?? 0].label)
                    isLabelFocused = false
                }
        }
    }

    @ViewBuilder
    private func sizeSection(rowIndex: Int, rowId: UUID) -> some View {
        Section("Screenshot Size") {
            Picker("Preset", selection: sizePresetBinding(for: rowId)) {
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
    }

    @ViewBuilder
    private func backgroundSection(rowIndex: Int, rowId: UUID) -> some View {
        Section("Background") {
            BackgroundEditor(
                backgroundStyle: safeRowBinding(rowId, keyPath: \.backgroundStyle, default: .color),
                bgColor: safeRowBinding(rowId, keyPath: \.bgColor, default: .blue),
                gradientConfig: safeRowBinding(rowId, keyPath: \.gradientConfig, default: GradientConfig()),
                backgroundImageConfig: safeRowBinding(rowId, keyPath: \.backgroundImageConfig, default: BackgroundImageConfig()),
                backgroundImage: state.rows[rowIndex].backgroundImageConfig.fileName.flatMap { state.screenshotImages[$0] },
                onChanged: { state.scheduleSave() },
                onPickImage: { state.pickAndSaveBackgroundImage(for: rowId) },
                onRemoveImage: { state.removeBackgroundImage(for: rowId) },
                onDropImage: { image in
                    state.saveBackgroundImage(image, for: rowId)
                }
            )

            if state.rows[rowIndex].backgroundStyle != .color {
                let canSpanAcrossRow = state.rows[rowIndex].templates.count > 1
                Toggle("Span across row", isOn: safeRowBinding(rowId, keyPath: \.spanBackgroundAcrossRow, default: false).onSet { state.scheduleSave() })
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
    }

    @ViewBuilder
    private func deviceSection(rowId: UUID) -> some View {
        Section("Device") {
            LabeledContent("Default device") {
                DevicePickerMenu(
                    category: defaultDeviceCategory(for: rowId),
                    frameId: defaultDeviceFrameId(for: rowId),
                    onSelectNone: {
                        guard let idx = state.rowIndex(for: rowId) else { return }
                        guard state.rows[idx].defaultDeviceCategory != nil || state.rows[idx].defaultDeviceFrameId != nil else { return }
                        state.rows[idx].defaultDeviceCategory = nil
                        state.rows[idx].defaultDeviceFrameId = nil
                        state.scheduleSave()
                    },
                    onSelectCategory: { cat in
                        guard let idx = state.rowIndex(for: rowId) else { return }
                        state.rows[idx].defaultDeviceCategory = cat
                        state.rows[idx].defaultDeviceFrameId = nil
                        state.scheduleSave()
                    },
                    onSelectFrame: { frame in
                        guard let idx = state.rowIndex(for: rowId) else { return }
                        state.rows[idx].defaultDeviceCategory = frame.fallbackCategory
                        state.rows[idx].defaultDeviceFrameId = frame.id
                        state.scheduleSave()
                    }
                )
                .help(defaultDeviceHelp(for: rowId))
            }
            .controlSize(.small)
            .font(.system(size: 12))

            // Body color only for abstract devices
            if defaultDeviceIsAbstract(for: rowId) {
                LabeledContent("Default body color") {
                    ColorPicker("", selection: rowDefaultDeviceBodyColorBinding(for: rowId), supportsOpacity: false)
                        .labelsHidden()
                        .help("Default device body color for this row")
                }
                .font(.system(size: 12))
            }
        }
    }

    private func defaultDeviceCategory(for rowId: UUID) -> DeviceCategory? {
        guard let idx = state.rowIndex(for: rowId) else { return .iphone }
        return state.rows[idx].defaultDeviceCategory
    }

    private func defaultDeviceFrameId(for rowId: UUID) -> String? {
        guard let idx = state.rowIndex(for: rowId) else { return nil }
        return state.rows[idx].defaultDeviceFrameId
    }

    private func defaultDeviceHelp(for rowId: UUID) -> String {
        guard let idx = state.rowIndex(for: rowId) else { return "Current default device: iPhone" }
        if let frameId = state.rows[idx].defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return "Current default device frame: \(frame.label)"
        }
        guard let category = state.rows[idx].defaultDeviceCategory else { return "No default device" }
        return "Current default abstract device: \(category.label)"
    }

    private func defaultDeviceIsAbstract(for rowId: UUID) -> Bool {
        guard let idx = state.rowIndex(for: rowId) else { return true }
        guard state.rows[idx].defaultDeviceCategory != nil else { return false }
        guard let frameId = state.rows[idx].defaultDeviceFrameId else { return true }
        return DeviceFrameCatalog.frame(for: frameId) == nil
    }

    @ViewBuilder
    private func optionsSection(rowId: UUID) -> some View {
        Section("Options") {
            Toggle("Show devices", isOn: safeRowBinding(rowId, keyPath: \.showDevice, default: true).onSet { state.scheduleSave() })
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Show borders", isOn: safeRowBinding(rowId, keyPath: \.showBorders, default: true).onSet { state.scheduleSave() })
                .font(.system(size: 12))
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private func sizePresetTag(for size: ScreenshotSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    private func safeRowBinding<T>(_ rowId: UUID, keyPath: WritableKeyPath<ScreenshotRow, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return defaultValue }
                return state.rows[idx][keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = state.rowIndex(for: rowId) else { return }
                state.rows[idx][keyPath: keyPath] = newValue
            }
        )
    }

    private func sizePresetBinding(for rowId: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return "" }
                return sizePresetTag(for: ScreenshotSize(
                    width: state.rows[idx].templateWidth,
                    height: state.rows[idx].templateHeight
                ))
            },
            set: { newValue in
                guard let size = parseSizeString(newValue),
                      let idx = state.rowIndex(for: rowId) else { return }
                state.resizeRow(at: idx, newWidth: size.width, newHeight: size.height)
            }
        )
    }

    private func rowDefaultDeviceBodyColorBinding(for rowId: UUID) -> Binding<Color> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return CanvasShapeModel.defaultDeviceBodyColor }
                return state.rows[idx].defaultDeviceBodyColor
            },
            set: {
                state.updateRowDefaultDeviceBodyColor($0, for: rowId)
            }
        )
    }

    private func spanAcrossRowHelp(for rowIndex: Int, canSpanAcrossRow: Bool) -> String {
        canSpanAcrossRow
            ? "Apply background across the entire row instead of repeating per screenshot"
            : "Requires at least two screenshots in the row"
    }
}
