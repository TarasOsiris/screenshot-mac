import SwiftUI

struct InspectorPanel: View {
    @Bindable var state: AppState
    @State private var isSizeExpanded = true
    @State private var useCustomSize = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""
    @State private var isBackgroundExpanded = true
    @State private var isAddElementExpanded = true
    @State private var isDeviceExpanded = true
    @State private var isVisibilityExpanded = true

    var body: some View {
        if let rowIndex = state.selectedRowIndex, let rowId = state.selectedRowId {
            Form {
                sizeSection(rowIndex: rowIndex, rowId: rowId)
                backgroundSection(rowIndex: rowIndex, rowId: rowId)
                Section(isExpanded: $isAddElementExpanded) {
                    ShapeToolbar(state: state)
                } header: {
                    Text("Shapes")
                }
                deviceSection(rowId: rowId)
                optionsSection(rowId: rowId)
            }
            .formStyle(.grouped)
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
    private func sizeSection(rowIndex: Int, rowId: UUID) -> some View {
        Section(isExpanded: $isSizeExpanded) {
            Picker("Mode", selection: $useCustomSize) {
                Text("Presets").tag(false)
                Text("Custom").tag(true)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .onChange(of: useCustomSize) { _, isCustom in
                if isCustom { syncCustomFields(rowId: rowId) }
            }
            .onChange(of: rowId) { _, newRowId in
                if useCustomSize { syncCustomFields(rowId: newRowId) }
            }

            if useCustomSize {
                customSizeFields(rowId: rowId)
            } else {
                presetPicker(rowId: rowId)
            }

            sizeLabel(rowIndex: rowIndex)
        } header: {
            Text("Screenshot Size")
        }
    }

    @ViewBuilder
    private func presetPicker(rowId: UUID) -> some View {
        Picker("Preset", selection: sizePresetBinding(for: rowId)) {
            ForEach(displayCategories) { category in
                Section(category.name) {
                    ForEach(category.sizes, id: \.label) { size in
                        Text(size.displayLabel)
                            .tag(sizePresetTag(for: size))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .controlSize(.small)
    }

    @ViewBuilder
    private func customSizeFields(rowId: UUID) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("W")
                    .frame(width: 14, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $customWidth)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { applyCustomSize(rowId: rowId) }
                Text("H")
                    .frame(width: 14, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $customHeight)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { applyCustomSize(rowId: rowId) }
            }
        }
        .font(.system(size: 11).monospacedDigit())
        .controlSize(.small)
    }

    @ViewBuilder
    private func sizeLabel(rowIndex: Int) -> some View {
        LabeledContent("Size") {
            Text(verbatim: state.rows[rowIndex].resolutionLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func syncCustomFields(rowId: UUID) {
        guard let idx = state.rowIndex(for: rowId) else { return }
        customWidth = "\(Int(state.rows[idx].templateWidth))"
        customHeight = "\(Int(state.rows[idx].templateHeight))"
    }

    private func applyCustomSize(rowId: UUID) {
        guard let w = Double(customWidth), let h = Double(customHeight),
              w >= 100, h >= 100,
              let idx = state.rowIndex(for: rowId) else { return }
        state.resizeRow(at: idx, newWidth: CGFloat(w), newHeight: CGFloat(h))
    }

    @ViewBuilder
    private func backgroundSection(rowIndex: Int, rowId: UUID) -> some View {
        Section(isExpanded: $isBackgroundExpanded) {
            BackgroundEditor(
                backgroundStyle: safeRowBinding(rowId, keyPath: \.backgroundStyle, default: .color),
                bgColor: safeRowBinding(rowId, keyPath: \.bgColor, default: .blue),
                gradientConfig: safeRowBinding(rowId, keyPath: \.gradientConfig, default: GradientConfig()),
                backgroundImageConfig: safeRowBinding(rowId, keyPath: \.backgroundImageConfig, default: BackgroundImageConfig()),
                backgroundImage: state.rows[rowIndex].backgroundImageConfig.fileName.flatMap { state.screenshotImages[$0] },
                onChanged: { },
                onPickImage: { state.pickAndSaveBackgroundImage(for: rowId) },
                onRemoveImage: { state.removeBackgroundImage(for: rowId) },
                onDropImage: { image in
                    state.saveBackgroundImage(image, for: rowId)
                }
            )

            HStack(spacing: 4) {
                Text("Blur")
                    .font(.system(size: 12))
                Spacer()
                Slider(
                    value: liveRowBinding(rowId, keyPath: \.backgroundBlur, default: 0),
                    in: 0...100
                ) { editing in
                    if editing {
                        guard let idx = state.rowIndex(for: rowId) else { return }
                        state.registerUndoForRow(at: idx, "Background Blur")
                    }
                }
                .frame(width: 100)
                Text("\(Int(state.rows[rowIndex].backgroundBlur))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .trailing)
            }

            if state.rows[rowIndex].backgroundStyle != .color {
                let canSpanAcrossRow = state.rows[rowIndex].templates.count > 1
                Toggle("Stretch across all screenshots", isOn: safeRowBinding(rowId, keyPath: \.spanBackgroundAcrossRow, default: false))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!canSpanAcrossRow)
                    .help(spanAcrossRowHelp(for: rowIndex, canSpanAcrossRow: canSpanAcrossRow))

                if !canSpanAcrossRow {
                    Text("Add at least two screenshots to stretch background across row.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Background")
        }
    }

    @ViewBuilder
    private func deviceSection(rowId: UUID) -> some View {
        Section(isExpanded: $isDeviceExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Default device")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                DevicePickerMenu(
                    category: defaultDeviceCategory(for: rowId),
                    frameId: defaultDeviceFrameId(for: rowId),
                    onSelectNone: {
                        state.setDefaultDevice(for: rowId, category: nil, frameId: nil)
                    },
                    onSelectCategory: { cat in
                        state.setDefaultDevice(for: rowId, category: cat, frameId: nil)
                    },
                    onSelectFrame: { frame in
                        state.setDefaultDevice(for: rowId, category: frame.fallbackCategory, frameId: frame.id)
                    }
                )
                .help(defaultDeviceHelp(for: rowId))
            }
            .controlSize(.small)

            // Body color only for abstract devices
            if defaultDeviceIsAbstract(for: rowId) {
                LabeledContent("Default color") {
                    ColorPicker("", selection: rowDefaultDeviceBodyColorBinding(for: rowId), supportsOpacity: false)
                        .labelsHidden()
                        .help("Default device color for this row")
                }
                .font(.system(size: 12))
            }
        } header: {
            Text("Device")
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
        Section(isExpanded: $isVisibilityExpanded) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                Toggle(isOn: safeRowBinding(rowId, keyPath: \.showBorders, default: true)) {
                    Label("Borders", systemImage: "rectangle.split.3x3")
                }
                ForEach(ShapeType.allCases, id: \.self) { type in
                    Toggle(isOn: shapeTypeVisibilityBinding(rowId: rowId, type: type)) {
                        Label(type.pluralLabel, systemImage: type.icon)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .controlSize(.small)
        } header: {
            HStack(spacing: 4) {
                Text("Visibility")
                Spacer()
                Button("Show All") { setVisibility(rowId: rowId, visible: true) }
                Button("Hide All") { setVisibility(rowId: rowId, visible: false) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
    }

    private func setVisibility(rowId: UUID, visible: Bool) {
        state.setAllShapeTypesVisibility(for: rowId, visible: visible)
    }

    private func shapeTypeVisibilityBinding(rowId: UUID, type: ShapeType) -> Binding<Bool> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return true }
                return !state.rows[idx].hiddenShapeTypes.contains(type)
            },
            set: { _ in
                state.toggleShapeTypeVisibility(for: rowId, type: type)
            }
        )
    }

    private func sizePresetTag(for size: ScreenshotSize) -> String {
        "\(Int(size.width))x\(Int(size.height))"
    }

    /// Binding that updates the row and schedules a save but does NOT register undo.
    /// Use with sliders where undo is registered once via `onEditingChanged`.
    private func liveRowBinding<T>(_ rowId: UUID, keyPath: WritableKeyPath<ScreenshotRow, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return defaultValue }
                return state.rows[idx][keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = state.rowIndex(for: rowId) else { return }
                state.rows[idx][keyPath: keyPath] = newValue
                state.scheduleSave()
            }
        )
    }

    private func safeRowBinding<T>(_ rowId: UUID, keyPath: WritableKeyPath<ScreenshotRow, T>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return defaultValue }
                return state.rows[idx][keyPath: keyPath]
            },
            set: { newValue in
                guard let idx = state.rowIndex(for: rowId) else { return }
                state.registerUndoForRow(at: idx, "Edit Row")
                state.rows[idx][keyPath: keyPath] = newValue
                state.scheduleSave()
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
