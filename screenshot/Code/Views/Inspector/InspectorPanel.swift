import SwiftUI

#if os(macOS)
private let sizeFieldLabelWidth: CGFloat = 14
private let blurValueWidth: CGFloat = 28
#else
private let sizeFieldLabelWidth: CGFloat = 20
private let blurValueWidth: CGFloat = 36
#endif

struct InspectorPanel: View {
    @Bindable var state: AppState
    #if DEBUG && os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @AppStorage("inspectorSizeExpanded") private var isSizeExpanded = true
    @AppStorage("inspectorBackgroundExpanded") private var isBackgroundExpanded = true
    @AppStorage("inspectorShapesExpanded") private var isAddElementExpanded = true
    @AppStorage("inspectorDeviceExpanded") private var isDeviceExpanded = true
    @AppStorage("inspectorVisibilityExpanded") private var isVisibilityExpanded = true
    @State private var useCustomSize = false
    @State private var customWidth: String = ""
    @State private var customHeight: String = ""

    var body: some View {
        if let rowIndex = state.selectedRowIndex, let rowId = state.selectedRowId {
            if state.previewingRows.contains(rowId) {
                previewModePanel(rowId: rowId)
            } else {
                Form {
                    sizeSection(rowIndex: rowIndex, rowId: rowId)
                    deviceSection(rowId: rowId)
                    backgroundSection(rowIndex: rowIndex, rowId: rowId)
                    Section(isExpanded: $isAddElementExpanded) {
                        ShapeToolbar(state: state)
                    } header: {
                        Text("Shapes")
                    }
                    visibilitySection(rowId: rowId)
                    #if DEBUG && os(iOS)
                    debugSection
                    #endif
                }
                .formStyle(.grouped)
                #if os(macOS)
                .coachPopover(step: .inspector, state: state, arrowEdge: .trailing)
                #else
                // Popovers attached to a Form don't anchor reliably on iPadOS.
                .coachPopoverAnchor(step: .inspector, state: state, arrowEdge: .trailing)
                #endif
            }
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
    private func previewModePanel(rowId: UUID) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.accentColor)
            Text("Preview Mode")
                .font(.headline)
            Text("This row is showing its templates as separate App Store-style tiles. Editing is disabled until you exit preview mode.")
                .font(.system(size: UIMetrics.FontSize.body))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                state.exitPreview(for: rowId)
            } label: {
                Label("Exit Preview Mode", systemImage: "pencil")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func sizeSection(rowIndex: Int, rowId: UUID) -> some View {
        Section(isExpanded: $isSizeExpanded) {
            Picker("Mode", selection: $useCustomSize) {
                Text("Presets").tag(false)
                Text("Custom").tag(true)
            }
            .pickerStyle(.segmented)
            .compactControlSize()
            .onChange(of: useCustomSize) { _, isCustom in
                if isCustom { syncCustomFields(rowId: rowId) }
            }
            .onChange(of: rowId) { _, newRowId in
                useCustomSize = !isPresetSize(rowId: newRowId)
                if useCustomSize { syncCustomFields(rowId: newRowId) }
            }
            .onAppear {
                useCustomSize = !isPresetSize(rowId: rowId)
                if useCustomSize { syncCustomFields(rowId: rowId) }
            }

            if useCustomSize {
                customSizeFields(rowId: rowId)
            } else {
                presetPicker(rowId: rowId)
            }
        } header: {
            Text("Screenshot Size")
        }
    }

    @ViewBuilder
    private func presetPicker(rowId: UUID) -> some View {
        let landscape = state.rowIndex(for: rowId).map { state.rows[$0].templateWidth > state.rows[$0].templateHeight } ?? false

        OrientationPicker(isLandscape: orientationBinding(for: rowId))

        Picker("Preset", selection: sizePresetBinding(for: rowId)) {
            ForEach(displayCategories) { category in
                Section(category.name) {
                    let sizesToShow = category.canonicalSizes
                    ForEach(sizesToShow, id: \.label) { baseSize in
                        let displaySize = category.isLandscapeOnly ? baseSize : baseSize.oriented(landscape: landscape)
                        Text(displaySize.compactLabel)
                            .tag(sizePresetTag(for: displaySize))
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .compactControlSize()
    }

    @ViewBuilder
    private func customSizeFields(rowId: UUID) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("W")
                    .frame(width: sizeFieldLabelWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $customWidth)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .integerKeyboard()
                    .onSubmit { applyCustomSize(rowId: rowId) }
                Text("H")
                    .frame(width: sizeFieldLabelWidth, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("", text: $customHeight)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .integerKeyboard()
                    .onSubmit { applyCustomSize(rowId: rowId) }
            }
        }
        .font(.system(size: UIMetrics.FontSize.body).monospacedDigit())
        .compactControlSize()
    }

    private func isPresetSize(rowId: UUID) -> Bool {
        guard let idx = state.rowIndex(for: rowId) else { return true }
        let w = state.rows[idx].templateWidth
        let h = state.rows[idx].templateHeight
        return displayCategories.contains { cat in
            cat.sizes.contains { $0.width == w && $0.height == h }
        }
    }

    private func orientationBinding(for rowId: UUID) -> Binding<Bool> {
        Binding(
            get: {
                guard let idx = state.rowIndex(for: rowId) else { return false }
                return state.rows[idx].templateWidth > state.rows[idx].templateHeight
            },
            set: { newLandscape in
                guard let idx = state.rowIndex(for: rowId) else { return }
                let w = state.rows[idx].templateWidth
                let h = state.rows[idx].templateHeight
                let currentlyLandscape = w > h
                if currentlyLandscape != newLandscape {
                    state.resizeRow(at: idx, newWidth: h, newHeight: w)
                }
            }
        )
    }

    private func syncCustomFields(rowId: UUID) {
        guard let idx = state.rowIndex(for: rowId) else { return }
        customWidth = "\(Int(state.rows[idx].templateWidth))"
        customHeight = "\(Int(state.rows[idx].templateHeight))"
    }

    private func applyCustomSize(rowId: UUID) {
        guard let w = Double(customWidth), let h = Double(customHeight),
              w >= 100, h >= 100, w <= 5000, h <= 5000,
              let idx = state.rowIndex(for: rowId) else { return }
        state.resizeRow(at: idx, newWidth: CGFloat(w), newHeight: CGFloat(h))
    }

    @ViewBuilder
    private func backgroundSection(rowIndex: Int, rowId: UUID) -> some View {
        Section(isExpanded: $isBackgroundExpanded) {
            BackgroundEditor(
                backgroundStyle: safeRowBinding(rowId, keyPath: \.backgroundStyle, default: .color),
                bgColor: safeRowBinding(rowId, keyPath: \.bgColor, default: .blue),
                gradientConfig: continuousRowBinding(rowId, keyPath: \.gradientConfig, default: GradientConfig()),
                backgroundImageConfig: continuousRowBinding(rowId, keyPath: \.backgroundImageConfig, default: BackgroundImageConfig()),
                backgroundImage: state.rows[rowIndex].backgroundImageConfig.fileName.flatMap { state.screenshotImages[$0] },
                onChanged: { },
                // macOS file-panel path; on iPad BackgroundImageEditor picks via ImageSourceMenu
                // and saves through onDropImage below.
                onPickImage: { state.pickAndSaveBackgroundImage(for: rowId) },
                onRemoveImage: { state.removeBackgroundImage(for: rowId) },
                onDropImage: { image in
                    state.saveBackgroundImage(image, for: rowId)
                },
                onDropSvg: { svgContent in
                    state.saveBackgroundSvg(svgContent, for: rowId)
                }
            )

            if state.rows[rowIndex].backgroundStyle != .color {
                HStack(spacing: 4) {
                    Text("Blur")
                        .font(.system(size: UIMetrics.FontSize.body))
                    Spacer()
                    Slider(
                        value: continuousRowBinding(rowId, keyPath: \.backgroundBlur, default: 0, actionName: "Background Blur"),
                        in: 0...100
                    )
                    .frame(width: 100)
                    Text("\(Int(state.rows[rowIndex].backgroundBlur))")
                        .font(.system(size: UIMetrics.FontSize.numericBadge).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: blurValueWidth, alignment: .trailing)
                }
            }

            if state.rows[rowIndex].backgroundStyle != .color {
                let canSpanAcrossRow = state.rows[rowIndex].templates.count > 1
                Toggle("Stretch across all screenshots", isOn: safeRowBinding(rowId, keyPath: \.spanBackgroundAcrossRow, default: false))
                    .font(.system(size: UIMetrics.FontSize.body))
                    .toggleStyle(.switch)
                    .compactControlSize()
                    .disabled(!canSpanAcrossRow)
                    .help(spanAcrossRowHelp(for: rowIndex, canSpanAcrossRow: canSpanAcrossRow))

                if !canSpanAcrossRow {
                    Text("Add at least two screenshots to stretch background across row.")
                        .font(.system(size: UIMetrics.FontSize.body))
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
                Text("Default device frame")
                    .font(.system(size: UIMetrics.FontSize.body))
                    .foregroundStyle(.secondary)
                DevicePickerMenu(
                    category: defaultDeviceCategory(for: rowId),
                    frameId: defaultDeviceFrameId(for: rowId),
                    presentation: .sidebar,
                    bodyColor: defaultDeviceIsAbstract(for: rowId) ? rowDefaultDeviceBodyColorBinding(for: rowId) : nil,
                    bodyColorLabel: String(localized: "Default color"),
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
            .compactControlSize()
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

    private func defaultDeviceHelp(for rowId: UUID) -> LocalizedStringKey {
        guard let idx = state.rowIndex(for: rowId) else { return "Current default device: iPhone" }
        if let frameId = state.rows[idx].defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
            return "Current default device frame: \(frame.label)"
        }
        guard let category = state.rows[idx].defaultDeviceCategory else { return "No default device" }
        return "Current default abstract device: \(category.label)"
    }

    private func defaultDeviceIsAbstract(for rowId: UUID) -> Bool {
        guard let idx = state.rowIndex(for: rowId) else { return true }
        guard let category = state.rows[idx].defaultDeviceCategory else { return false }
        if category == .invisible { return false }
        guard let frameId = state.rows[idx].defaultDeviceFrameId else { return true }
        return DeviceFrameCatalog.frame(for: frameId) == nil
    }

    @ViewBuilder
    private func visibilityToggles(rowId: UUID) -> some View {
        Toggle(isOn: safeRowBinding(rowId, keyPath: \.showBorders, default: true)) {
            Label("Borders", systemImage: "rectangle.split.3x3")
        }
        ForEach(ShapeType.allCases, id: \.self) { type in
            Toggle(isOn: shapeTypeVisibilityBinding(rowId: rowId, type: type)) {
                Label(type.pluralLabel, systemImage: type.icon)
            }
        }
    }

    @ViewBuilder
    private func visibilitySection(rowId: UUID) -> some View {
        Section(isExpanded: $isVisibilityExpanded) {
            #if os(macOS)
            HStack(spacing: 6) {
                Button("Show All") { setVisibility(rowId: rowId, visible: true) }
                Button("Hide All") { setVisibility(rowId: rowId, visible: false) }
                Spacer()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .font(.system(size: UIMetrics.FontSize.body))

            // macOS packs checkbox toggles into two compact columns.
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                visibilityToggles(rowId: rowId)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: UIMetrics.FontSize.body))
            .controlSize(.small)
            #else
            // iPad needs comfortable touch targets — full-width buttons at regular size.
            HStack(spacing: 12) {
                Button("Show All") { setVisibility(rowId: rowId, visible: true) }
                    .frame(maxWidth: .infinity)
                Button("Hide All") { setVisibility(rowId: rowId, visible: false) }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            // iPad renders each toggle as a native full-width Form row (label + switch).
            visibilityToggles(rowId: rowId)
            #endif
        } header: {
            Text("Visibility")
        }
    }

    private func setVisibility(rowId: UUID, visible: Bool) {
        state.setAllShapeTypesVisibility(for: rowId, visible: visible)
    }

    #if DEBUG && os(iOS)
    private var debugSection: some View {
        Section {
            Button {
                state.startCoach(persistOnEnd: false)
            } label: {
                Text(verbatim: "Show Onboarding Coach")
            }
        } header: {
            Text(verbatim: "Debug")
        } footer: {
            Text(verbatim: "Starts the editor tour without consuming the real onboarding flag.")
        }
    }
    #endif

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
    /// Like `safeRowBinding` but routes writes through `updateRowContinuous`, so a
    /// drag burst (gradient stops/angle/center, image sliders) collapses into one
    /// undo entry instead of registering a full-row snapshot per tick.
    private func continuousRowBinding<T>(_ rowId: UUID, keyPath: WritableKeyPath<ScreenshotRow, T>, default defaultValue: T, actionName: String = "Edit Background") -> Binding<T> {
        Binding(
            get: {
                if state.continuousRowEditId == rowId, let row = state.continuousRowEditWorkingRow {
                    return row[keyPath: keyPath]
                }
                guard let idx = state.rowIndex(for: rowId) else { return defaultValue }
                return state.rows[idx][keyPath: keyPath]
            },
            set: { newValue in
                state.updateRowContinuous(rowId, actionName: actionName) { $0[keyPath: keyPath] = newValue }
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
                state.withUndo("Edit Row") {
                    state.rows[idx][keyPath: keyPath] = newValue
                }
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

    private func spanAcrossRowHelp(for rowIndex: Int, canSpanAcrossRow: Bool) -> LocalizedStringKey {
        canSpanAcrossRow
            ? "Apply background across the entire row instead of repeating per screenshot"
            : "Requires at least two screenshots in the row"
    }
}
