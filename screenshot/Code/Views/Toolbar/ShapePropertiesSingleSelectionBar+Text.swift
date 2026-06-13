import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Text Popover

    @ViewBuilder
    func textPopoverButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextPopoverPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "textformat")
                Text(textPopoverSummary(shape: shape))
                    .monospacedDigit()
                    .lineLimit(1)
                    .transaction { $0.animation = nil }
            }
        }
        .buttonStyle(.borderless)
        .help("Text")
        .barPopover(isPresented: $isTextPopoverPresented, title: "Text") {
            textPopoverContent(shape: shape, shapeId: shapeId)
        }
    }

    func textPopoverSummary(shape: CanvasShapeModel) -> String {
        let fontName = shape.fontName?.isEmpty == false ? shape.fontName! : "System"
        let size = Int(shape.fontSize ?? Self.defaultFontSize)
        let controlState = CustomFontRegistry.controlState(for: shape)
        let weight = RichTextUtils.fontWeightLabel(controlState?.effectiveWeight ?? shape.fontWeight ?? 400)
        return "\(fontName) \(size) \(weight)"
    }

    @ViewBuilder
    func textPopoverContent(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        #if os(macOS)
        textPopoverColumn(shape: shape, shapeId: shapeId)
            .font(.system(size: UIMetrics.FontSize.body))
            .controlSize(.small)
            .padding(12)
            .barPopoverContentWidth(280)
        #else
        textPopoverForm(shape: shape, shapeId: shapeId)
        #endif
    }

    // MARK: - macOS dense column

    #if os(macOS)
    @ViewBuilder
    private func textPopoverColumn(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        let customControlState = CustomFontRegistry.controlState(for: shape)

        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Font") {
                fontPickerControl(shapeId: shapeId)
            }

            LabeledContent("Size") {
                HStack(spacing: 4) {
                    fontSizeField(shape: shape, shapeId: shapeId)

                    if customControlState?.showsWeightPicker ?? true {
                        fontWeightControl(shapeId: shapeId, customControlState: customControlState)
                    }
                }
            }

            Divider()

            LabeledContent("Align") {
                HStack(spacing: 8) {
                    horizontalAlignPicker(shapeId: shapeId)
                        .frame(width: 90)
                    verticalAlignPicker(shapeId: shapeId)
                        .frame(width: 90)
                }
            }

            HStack(spacing: 12) {
                if customControlState?.showsItalicToggle ?? true {
                    Toggle("Italic", isOn: italicBinding(shapeId))
                        .toggleStyle(.switch)
                        .compactControlSize()
                }

                Toggle("Uppercase", isOn: shapeBinding(shapeId, \.uppercase, default: false))
                    .toggleStyle(.switch)
                    .compactControlSize()
            }

            Divider()

            LabeledContent("Letter Spacing") {
                letterSpacingControl(shapeId: shapeId, sliderWidth: UIMetrics.SliderWidth.wide)
            }

            LabeledContent("Line Spacing") {
                lineSpacingField(shape: shape, shapeId: shapeId)
            }

            if shape.hasRichText {
                Divider()
                clearFormattingButton(shapeId: shapeId)
                    .font(.system(size: UIMetrics.FontSize.body))
            }
        }
    }
    #endif

    // MARK: - iOS native form

    #if os(iOS)
    @ViewBuilder
    private func textPopoverForm(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        let customControlState = CustomFontRegistry.controlState(for: shape)

        Form {
            Section("Font") {
                fontPickerControl(shapeId: shapeId)

                if customControlState?.showsWeightPicker ?? true {
                    LabeledContent("Weight") {
                        fontWeightControl(shapeId: shapeId, customControlState: customControlState)
                    }
                }
            }

            Section("Size") {
                LabeledContent("Size") {
                    fontSizeField(shape: shape, shapeId: shapeId)
                }
            }

            Section("Alignment") {
                horizontalAlignPicker(shapeId: shapeId)
                verticalAlignPicker(shapeId: shapeId)
            }

            Section("Style") {
                if customControlState?.showsItalicToggle ?? true {
                    Toggle("Italic", isOn: italicBinding(shapeId))
                }
                Toggle("Uppercase", isOn: shapeBinding(shapeId, \.uppercase, default: false))
            }

            Section("Spacing") {
                LabeledContent("Letter Spacing") {
                    letterSpacingControl(shapeId: shapeId, sliderWidth: UIMetrics.SliderWidth.standard)
                }
                LabeledContent("Line Spacing") {
                    lineSpacingField(shape: shape, shapeId: shapeId)
                }
            }

            if shape.hasRichText {
                Section {
                    clearFormattingButton(shapeId: shapeId)
                }
            }
        }
    }
    #endif

    // MARK: - Shared controls

    @ViewBuilder
    private func fontPickerControl(shapeId: UUID) -> some View {
        FontPicker(
            selection: shapeBinding(shapeId, \.fontName, default: ""),
            fontWeight: fontWeightBinding(shapeId),
            italic: italicBinding(shapeId),
            customFonts: state.customFonts,
            onApplyImportedSelection: { imported in
                applyImportedFontSelection(imported, to: shapeId)
            },
            onImportFont: { url in state.importCustomFont(from: url) }
        )
    }

    @ViewBuilder
    private func fontWeightControl(shapeId: UUID, customControlState: CustomFontControlState?) -> some View {
        FontWeightPicker(
            selection: fontWeightBinding(shapeId),
            options: customControlState?.availableWeights ?? [300, 400, 500, 700],
            width: 100
        )
    }

    @ViewBuilder
    private func fontSizeField(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        HStack(spacing: 0) {
            TextField("", text: $editingFontSize, onEditingChanged: { editing in
                if editing {
                    isFontSizeFieldActive = true
                } else {
                    commitFontSize(to: state.selectedShapeId ?? shapeId)
                }
            })
            .focused($focusedField, equals: .fontSize)
            .frame(width: propertiesFontFieldWidth)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .integerKeyboard()
            .onAppear {
                editingFontSize = currentFontSizeString(for: shapeId)
            }
            .onChange(of: shapeId) { oldId, newId in
                // Flush to the shape we were editing before rebinding — see the
                // opacity field; the captured shapeId goes stale otherwise.
                if isFontSizeFieldActive { commitFontSize(to: oldId) }
                editingFontSize = currentFontSizeString(for: newId)
            }
            .onChange(of: shape.fontSize) {
                guard !isFontSizeFieldActive else { return }
                editingFontSize = currentFontSizeString(for: shapeId)
            }
            .onChange(of: editingFontSize) {
                guard isFontSizeFieldActive else { return }
                let target = state.selectedShapeId ?? shapeId
                if let value = Int(editingFontSize), let i = idx(for: target) {
                    var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                    resolved.fontSize = clampedFontSize(value)
                    RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .fontSize)
                    state.updateShapeContinuous(resolved)
                }
            }

            presetChevronMenu {
                ForEach(Self.fontSizePresets, id: \.self) { size in
                    Button("\(size)") {
                        editingFontSize = "\(size)"
                        commitFontSize(to: state.selectedShapeId ?? shapeId)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func horizontalAlignPicker(shapeId: UUID) -> some View {
        Picker("", selection: shapeBinding(shapeId, \.textAlign, default: .center)) {
            Image(systemName: "text.alignleft").tag(TextAlign.left)
            Image(systemName: "text.aligncenter").tag(TextAlign.center)
            Image(systemName: "text.alignright").tag(TextAlign.right)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Horizontal alignment")
    }

    @ViewBuilder
    private func verticalAlignPicker(shapeId: UUID) -> some View {
        Picker("", selection: shapeBinding(shapeId, \.textVerticalAlign, default: .center)) {
            Image(systemName: "arrow.up.to.line").tag(TextVerticalAlign.top)
            Image(systemName: "arrow.up.and.down").tag(TextVerticalAlign.center)
            Image(systemName: "arrow.down.to.line").tag(TextVerticalAlign.bottom)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Vertical alignment")
    }

    @ViewBuilder
    private func letterSpacingControl(shapeId: UUID, sliderWidth: CGFloat) -> some View {
        let trackingBinding = shapeBinding(shapeId, \.letterSpacing, default: 0, continuous: true)
        HStack(spacing: 4) {
            Slider(value: trackingBinding, in: -5...30)
                .frame(width: sliderWidth)

            Text(verbatim: String(format: "%.1f", trackingBinding.wrappedValue))
                .frame(width: propertiesTrackingValueWidth, alignment: .trailing)
                .onTapGesture(count: 2) { trackingBinding.wrappedValue = 0 }
                #if os(macOS)
                .help("Double-click to reset")
                #else
                .help("Double-tap to reset")
                #endif
        }
    }

    @ViewBuilder
    private func lineSpacingField(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        HStack(spacing: 0) {
            TextField("", text: $editingLineHeight, onEditingChanged: { editing in
                if editing {
                    isLineHeightFieldActive = true
                } else {
                    commitLineHeight(to: state.selectedShapeId ?? shapeId)
                }
            })
            .focused($focusedField, equals: .lineHeight)
            .frame(width: propertiesFontFieldWidth)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .integerKeyboard()
            .onAppear {
                editingLineHeight = currentLineHeightString(for: shapeId)
            }
            .onChange(of: shapeId) { oldId, newId in
                // Flush to the shape we were editing before rebinding (see opacity).
                if isLineHeightFieldActive { commitLineHeight(to: oldId) }
                editingLineHeight = currentLineHeightString(for: newId)
            }
            .onChange(of: shape.lineHeightMultiple) {
                guard !isLineHeightFieldActive else { return }
                editingLineHeight = currentLineHeightString(for: shapeId)
            }
            .onChange(of: editingLineHeight) {
                guard isLineHeightFieldActive else { return }
                let target = state.selectedShapeId ?? shapeId
                if let value = Int(editingLineHeight), let i = idx(for: target) {
                    var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
                    resolved.lineHeightMultiple = TextLayoutStyle.clampLineHeightMultiple(CGFloat(value) / 100.0)
                    resolved.lineSpacing = nil
                    RichTextUtils.syncShapeStyleIfNeeded(in: &resolved, property: .lineHeight)
                    state.updateShapeContinuous(resolved)
                }
            }

            presetChevronMenu {
                ForEach(Self.lineHeightPresets, id: \.self) { preset in
                    Button("\(preset)%") {
                        editingLineHeight = "\(preset)"
                        commitLineHeight(to: state.selectedShapeId ?? shapeId)
                    }
                }
            }

            Text("%")
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }

    @ViewBuilder
    private func presetChevronMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Menu {
            content()
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: UIMetrics.FontSize.hint))
                .foregroundStyle(.secondary)
                .frame(width: UIMetrics.ChevronMenu.width, height: UIMetrics.ChevronMenu.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder
    private func clearFormattingButton(shapeId: UUID) -> some View {
        Button("Clear Formatting") {
            guard let i = idx(for: shapeId) else { return }
            var updated = resolvedShape(at: i.row, shapeIdx: i.shape)
            updated.richText = nil
            state.updateShape(updated)
        }
    }
}
