#if os(macOS)
import SwiftUI

extension ShapeInspector {
    @ViewBuilder
    func geometrySection(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        Section(isExpanded: $isGeometryExpanded) {
            ShapeGeometryFields(state: state, shapeId: shapeId, shape: shape, layout: .formRows)
            LabeledContent("Rotation") {
                ShapeRotationControl(state: state, shapeId: shapeId)
            }
        } header: {
            sectionHeader("Position & Size", .geometry, fields)
        }
    }

    @ViewBuilder
    func typeSections(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        switch shape.type {
        case .device:
            deviceSection(shape: shape, fields: fields)
            if shape.supportsDeviceModelRotation {
                device3DSection(shape: shape)
            }
        case .text:
            textSection(shape: shape, fields: fields)
            textBackgroundSection
        case .image:
            imageSection(shape: shape, fields: fields)
        case .svg:
            svgSection(shape: shape)
        case .rectangle, .circle, .star:
            EmptyView()
        }
    }

    // MARK: - Device

    @ViewBuilder
    private func deviceSection(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        Section(isExpanded: $isDeviceExpanded) {
            devicePicker(shape: shape, shapeId: shapeId, presentation: .sidebar)

            if shape.screenshotFileName != nil {
                replaceImageRow(title: "Replace Image")
            }

            if shape.deviceCategory == .androidPhone && shape.deviceFrameId == nil {
                AndroidCameraCutoutToggle(hideCameraCutout: shapeBinding(shapeId, \.hideCameraCutout, default: false))
            }
        } header: {
            sectionHeader("Device", .media, fields)
        }
    }

    @ViewBuilder
    private func device3DSection(shape: CanvasShapeModel) -> some View {
        Section(isExpanded: $is3DExpanded) {
            Device3DAppearanceControls(
                pitch: deviceModelRotationBinding(shapeId, \.devicePitch, defaultValue: \.resolvedDevicePitch),
                yaw: deviceModelRotationBinding(shapeId, \.deviceYaw, defaultValue: \.resolvedDeviceYaw),
                material: optionalConfigBinding(shapeId, \.deviceBodyMaterial, fallback: DeviceBodyMaterial(), isEmpty: \.isEmpty),
                lighting: optionalConfigBinding(shapeId, \.deviceLighting, fallback: DeviceLighting(), isEmpty: \.isEmpty)
            )

            PopoverResetButton(label: "Reset all", isDisabled: { !hasDevice3DAppearanceOverride(shapeId) }) {
                resetDevice3DAppearance(shapeId)
            }
            .help("Reset rotation, material, and lighting to defaults")
        } header: {
            InspectorSectionHeader("3D Device") {
                PopoverBadge(text: "Beta", help: "3D device rendering is an experimental feature")
            }
        }
    }

    // MARK: - Text

    @ViewBuilder
    private func textSection(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        let customControlState = CustomFontRegistry.controlState(for: shape)

        Section(isExpanded: $isTextExpanded) {
            LabeledContent("Font") {
                TextFontPickerControl(state: state, shapeId: shapeId)
            }
            .localeOverridden(.font)

            LabeledContent("Size") {
                HStack(spacing: 4) {
                    // Marked per control, not on the row: a row-level wash would stack with the
                    // weight picker's own when both are overridden.
                    TextFontSizeField(state: state, shapeId: shapeId)
                        .localeOverridden(.fontSize)
                    if customControlState?.showsWeightPicker ?? true {
                        TextFontWeightControl(state: state, shapeId: shapeId, customControlState: customControlState)
                            .localeOverridden(.fontWeight)
                    }
                }
            }

            LabeledContent("Color") {
                ColorPicker("Color", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                    .labelsHidden()
            }

            LabeledContent("Align") {
                VStack(alignment: .trailing, spacing: 6) {
                    TextAlignPicker(selection: shapeBinding(shapeId, \.textAlign, default: .center))
                        .fixedSize()
                        .localeOverridden(.textAlign)
                    TextVerticalAlignPicker(selection: shapeBinding(shapeId, \.textVerticalAlign, default: .center))
                        .fixedSize()
                }
            }

            if customControlState?.showsItalicToggle ?? true {
                Toggle("Italic", isOn: italicBinding(shapeId))
                    .toggleStyle(.switch)
                    .localeOverridden(.italic)
            }

            Toggle("Uppercase", isOn: shapeBinding(shapeId, \.uppercase, default: false))
                .toggleStyle(.switch)
                .localeOverridden(.uppercase)

            LabeledContent("Letter Spacing") {
                TextLetterSpacingControl(state: state, shapeId: shapeId, sliderWidth: UIMetrics.SliderWidth.standard)
            }
            .localeOverridden(.letterSpacing)

            LabeledContent("Line Spacing") {
                TextLineSpacingField(state: state, shapeId: shapeId)
            }
            // This control writes `lineHeightMultiple`; `lineSpacing` is the legacy field.
            .localeOverridden(.lineHeight)

            if shape.hasRichText {
                TextClearFormattingButton(state: state, shapeId: shapeId)
            }
        } header: {
            sectionHeader("Text", .typography, fields)
        }
    }

    private var textBackgroundSection: some View {
        Section(isExpanded: $isTextBackgroundExpanded) {
            TextBackgroundControls(state: state, shapeId: shapeId, wrapsPresets: true)
        } header: {
            InspectorSectionHeader("Text Background")
        }
    }

    // MARK: - Image & SVG

    @ViewBuilder
    private func imageSection(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        Section(isExpanded: $isMediaExpanded) {
            replaceImageRow(title: shape.imageFileName != nil ? "Replace Image" : "Choose Image")
        } header: {
            sectionHeader("Image", .media, fields)
        }
    }

    @ViewBuilder
    private func svgSection(shape: CanvasShapeModel) -> some View {
        Section(isExpanded: $isMediaExpanded) {
            Toggle("Custom color", isOn: shapeBinding(shapeId, \.svgUseColor, default: false))
                .toggleStyle(.switch)
                .help("Use custom color for SVG")

            if shape.svgUseColor == true {
                LabeledContent("Color") {
                    ColorPicker("SVG custom color", selection: shapeBinding(shapeId, \.color), supportsOpacity: false)
                        .labelsHidden()
                }
            }

            Button {
                isReplacingSvg = true
            } label: {
                Label("Replace SVG", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            InspectorSectionHeader("SVG")
        }
    }

    private func replaceImageRow(title: LocalizedStringKey) -> some View {
        Button {
            pickAndReplaceImage(for: shapeId)
        } label: {
            Label(title, systemImage: "photo.badge.arrow.down")
        }
        .localeOverridden(.image)
    }

    // MARK: - Appearance

    @ViewBuilder
    func appearanceSection(shape: CanvasShapeModel) -> some View {
        Section(isExpanded: $isAppearanceExpanded) {
            LabeledContent("Opacity") {
                ShapeOpacityField(state: state, shapeId: shapeId, showsSlider: true)
            }

            if shape.supportsCornerRadius {
                PopoverSliderRow(label: "Radius", value: shapeBinding(shapeId, \.borderRadius, continuous: true), range: 0...500, layout: .form)
            }

            if shape.type == .star {
                LabeledContent("Points") {
                    Stepper(
                        value: shapeBinding(shapeId, \.starPointCount, default: CanvasShapeModel.defaultStarPointCount),
                        in: 3...20
                    ) {
                        Text(verbatim: "\(shape.starPointCount ?? CanvasShapeModel.defaultStarPointCount)")
                            .monospacedDigit()
                    }
                }
            }

            Toggle("Clip to Frame", isOn: shapeBinding(shapeId, \.clipToTemplate, default: false))
                .toggleStyle(.switch)
        } header: {
            InspectorSectionHeader("Appearance")
        }
    }

    @ViewBuilder
    func fillSection(shape: CanvasShapeModel) -> some View {
        if shape.type.supportsFill {
            Section(isExpanded: $isFillExpanded) {
                BackgroundEditor(
                    backgroundStyle: fillStyleBinding(shapeId),
                    bgColor: shapeBinding(shapeId, \.color),
                    gradientConfig: shapeBinding(shapeId, \.fillGradientConfig, default: GradientConfig(), continuous: true),
                    backgroundImageConfig: shapeBinding(shapeId, \.fillImageConfig, default: BackgroundImageConfig(), continuous: true),
                    backgroundImage: shapeFillImage(shapeId),
                    onChanged: { state.scheduleSave() },
                    onPickImage: { isReplacingFillImage = true },
                    onRemoveImage: { state.removeShapeFillImage(for: shapeId) },
                    onDropImage: { image in state.saveShapeFillImage(image, for: shapeId) }
                )
            } header: {
                InspectorSectionHeader("Fill")
            }
        }
    }

    @ViewBuilder
    func outlineSection(shape: CanvasShapeModel) -> some View {
        if shape.supportsOutlineEditing {
            Section(isExpanded: $isOutlineExpanded) {
                InspectorOutlineRows(
                    isOn: outlineEnabledBinding(shapeId),
                    color: shapeBinding(shapeId, \.outlineColor, default: CanvasShapeModel.defaultOutlineColor),
                    width: shapeBinding(shapeId, \.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth, continuous: true),
                    showsDetails: (shape.outlineWidth ?? 0) > 0
                )
            } header: {
                InspectorSectionHeader("Outline")
            }
        }
    }

    var shadowSection: some View {
        let shadow = optionalConfigBinding(shapeId, \.shadow, fallback: ShadowConfig(), isEmpty: \.isEmpty)

        return Section(isExpanded: $isShadowExpanded) {
            ShadowControls(shadow: shadow)

            PopoverResetButton(label: "Reset", isDisabled: { resolvedDocumentShape(shapeId)?.shadow == nil }) {
                shadow.wrappedValue = ShadowConfig()
            }
            .help("Remove the shadow")
        } header: {
            InspectorSectionHeader("Shadow")
        }
    }

    // MARK: - Localization

    @ViewBuilder
    func localizationSection(shape: CanvasShapeModel, fields: Set<LocaleOverrideField>) -> some View {
        if shape.type == .text && state.localeState.nonBaseLocaleCount > 0 {
            Section(isExpanded: $isLocalizationExpanded) {
                Button("Edit Translations...") {
                    isLocalizationPopoverPresented = true
                }
                .popover(isPresented: $isLocalizationPopoverPresented, arrowEdge: .leading) {
                    TextLocalizationControls(state: state, shapeId: shapeId, fallbackShape: shape) {
                        isLocalizationPopoverPresented = false
                    }
                }
            } header: {
                sectionHeader("Localization", .translation, fields)
            }
        }
    }
}
#endif
