import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Text Popover

    @ViewBuilder
    func textPopoverButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        PropertiesBarPopoverTrigger(
            systemImage: "textformat",
            isPresented: $isTextPopoverPresented,
            help: "Text",
            popoverTitle: "Text"
        ) {
            Text(verbatim: textPopoverSummary(shape: shape))
                .monospacedDigit()
                .lineLimit(1)
                .transaction { $0.animation = nil }
        } content: {
            textPopoverContent(shapeId: shapeId)
        }
    }

    func textPopoverSummary(shape: CanvasShapeModel) -> String {
        let fontName = shape.fontName?.isEmpty == false ? shape.fontName! : "System"
        let size = Int(shape.fontSize ?? Self.defaultFontSize)
        let controlState = CustomFontRegistry.controlState(for: shape)
        let weight = RichTextUtils.fontWeightLabel(controlState?.effectiveWeight ?? shape.fontWeight ?? 400)
        return "\(fontName) \(size) \(weight)"
    }

    /// Resolves the shape here rather than taking it as a parameter: the iPad docked panel holds
    /// this closure across updates, so a shape captured at open time would go stale.
    @ViewBuilder
    func textPopoverContent(shapeId: UUID) -> some View {
        if let shape = liveShape(shapeId) {
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
            options: customControlState?.availableWeights ?? [300, 400, 500, 700]
        )
    }

    @ViewBuilder
    private func fontSizeField(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        HStack(spacing: 0) {
            ShapePropertyField(
                shapeId: shapeId,
                field: .fontSize,
                text: $editingFontSize,
                isActive: $isFontSizeFieldActive,
                focus: $focusedField,
                width: propertiesFontFieldWidth,
                modelValue: shape.fontSize.map(Double.init),
                current: { currentFontSizeString(for: $0) },
                commit: { commitFontSize(to: $0) },
                liveApply: { applyFontSizeContinuously(fallbackShapeId: shapeId) },
                liveSelection: { state.selectedShapeId }
            )

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

            Text(trackingBinding.wrappedValue, format: .number.precision(.fractionLength(1)))
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
            ShapePropertyField(
                shapeId: shapeId,
                field: .lineHeight,
                text: $editingLineHeight,
                isActive: $isLineHeightFieldActive,
                focus: $focusedField,
                width: propertiesFontFieldWidth,
                modelValue: shape.lineHeightMultiple.map(Double.init),
                current: { currentLineHeightString(for: $0) },
                commit: { commitLineHeight(to: $0) },
                liveApply: { applyLineHeightContinuously(fallbackShapeId: shapeId) },
                liveSelection: { state.selectedShapeId }
            )

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
