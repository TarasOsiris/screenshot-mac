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
        let size = Int(shape.fontSize ?? CanvasShapeModel.defaultFontSize)
        let controlState = CustomFontRegistry.controlState(for: shape)
        let weight = RichTextUtils.fontWeightLabel(controlState?.effectiveWeight ?? shape.fontWeight ?? 400)
        return "\(fontName) \(size) \(weight)"
    }

    /// Resolves the shape here rather than taking it as a parameter: the iPad docked panel holds
    /// this closure across updates, so a shape captured at open time would go stale.
    @ViewBuilder
    func textPopoverContent(shapeId: UUID) -> some View {
        if let shape = editingShape(shapeId) {
            #if os(macOS)
            textPopoverColumn(shape: shape, shapeId: shapeId)
                .scaledFont(UIMetrics.FontSize.body)
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
            EditorLabeledContent("Font") {
                TextFontPickerControl(state: state, shapeId: shapeId)
            }

            EditorLabeledContent("Size") {
                HStack(spacing: 4) {
                    TextFontSizeField(state: state, shapeId: shapeId)

                    if customControlState?.showsWeightPicker ?? true {
                        TextFontWeightControl(state: state, shapeId: shapeId, customControlState: customControlState)
                    }
                }
            }

            Divider()

            EditorLabeledContent("Align") {
                HStack(spacing: 8) {
                    TextAlignPicker(selection: shapeBinding(shapeId, \.textAlign, default: .center))
                        .frame(width: 90)
                    TextVerticalAlignPicker(selection: shapeBinding(shapeId, \.textVerticalAlign, default: .center))
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

            EditorLabeledContent("Letter Spacing") {
                TextLetterSpacingControl(state: state, shapeId: shapeId, sliderWidth: UIMetrics.SliderWidth.wide)
            }

            EditorLabeledContent("Line Spacing") {
                TextLineSpacingField(state: state, shapeId: shapeId)
            }

            if shape.hasRichText {
                Divider()
                TextClearFormattingButton(state: state, shapeId: shapeId)
                    .scaledFont(UIMetrics.FontSize.body)
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
                TextFontPickerControl(state: state, shapeId: shapeId)

                if customControlState?.showsWeightPicker ?? true {
                    EditorLabeledContent("Weight") {
                        TextFontWeightControl(state: state, shapeId: shapeId, customControlState: customControlState)
                    }
                }
            }

            Section("Size") {
                EditorLabeledContent("Size") {
                    TextFontSizeField(state: state, shapeId: shapeId)
                }
            }

            Section("Alignment") {
                TextAlignPicker(selection: shapeBinding(shapeId, \.textAlign, default: .center))
                TextVerticalAlignPicker(selection: shapeBinding(shapeId, \.textVerticalAlign, default: .center))
            }

            Section("Style") {
                if customControlState?.showsItalicToggle ?? true {
                    Toggle("Italic", isOn: italicBinding(shapeId))
                }
                Toggle("Uppercase", isOn: shapeBinding(shapeId, \.uppercase, default: false))
            }

            Section("Spacing") {
                EditorLabeledContent("Letter Spacing") {
                    TextLetterSpacingControl(state: state, shapeId: shapeId, sliderWidth: UIMetrics.SliderWidth.standard)
                }
                EditorLabeledContent("Line Spacing") {
                    TextLineSpacingField(state: state, shapeId: shapeId)
                }
            }

            if shape.hasRichText {
                Section {
                    TextClearFormattingButton(state: state, shapeId: shapeId)
                }
            }
        }
    }
    #endif
}
