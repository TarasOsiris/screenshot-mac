import SwiftUI

struct ShapePropertiesMultiSelectionBar: View, MultiShapeEditing {
    @Bindable var state: AppState

    var body: some View {
        let shapes = selectedShapes
        let count = shapes.count
        let commonType = commonShapeType(of: shapes)

        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if let type = commonType {
                            Image(systemName: type.icon)
                                .scaledFont(UIMetrics.FontSize.body, weight: .medium)
                        }
                        Text("\(count) shapes")
                            .scaledFont(UIMetrics.FontSize.body, weight: .semibold)
                    }
                    .propertiesBadgeCapsule()

                    if let commonType {
                        multiSelectionTypeControls(commonType, shapes: shapes)

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Opacity") {
                                let opacity = multiShapeBinding(\.opacity)
                                Slider(value: opacity, in: 0...1)
                                    .frame(width: UIMetrics.SliderWidth.standard)
                                Text(verbatim: "\(Int((opacity.wrappedValue * 100).rounded()))%")
                                    .scaledFont(UIMetrics.FontSize.numericBadge)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: propertiesOpacityFieldWidth, alignment: .trailing)
                            }
                        }

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Rotation") {
                                let rotation = multiShapeBinding(\.rotation)
                                Slider(value: rotation, in: 0...360)
                                    .frame(width: UIMetrics.SliderWidth.standard)

                                Text(verbatim: "\(Int(rotation.wrappedValue.rounded()))°")
                                    .scaledFont(UIMetrics.FontSize.numericBadge)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .frame(width: propertiesNumericFieldWidth, alignment: .trailing)

                                if shapes.contains(where: { $0.rotation != 0 }) {
                                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset rotation", frameSize: UIMetrics.IconButton.frameSize) {
                                        resetRotationOnSelection()
                                    }
                                }
                            }
                        }

                        ShapeClipToFrameSection(clipToTemplate: multiShapeOptionalBinding(\.clipToTemplate, default: false))
                    }

                    ShapePropertiesSection {
                        ShapeSelectionActionButtons(
                            onBringToFront: { state.bringSelectedShapesToFront() },
                            onSendToBack: { state.sendSelectedShapesToBack() },
                            onDuplicate: { state.duplicateSelectedShapes() },
                            onDelete: { state.deleteSelectedShapes() }
                        )
                    }
                }
                .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
                .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)

            ActionButton(icon: "xmark", tooltip: "Deselect all (Esc)", frameSize: UIMetrics.IconButton.frameSize) {
                state.selectedShapeIds = []
            }
            .padding(.trailing, 8)
        }
        .scaledFont(UIMetrics.FontSize.body)
        .compactControlSize()
        .denseBarTypography()
        .modifier(PropertiesBarChrome())
    }

    @ViewBuilder
    private func multiSelectionTypeControls(_ type: ShapeType, shapes: [CanvasShapeModel]) -> some View {
        if type == .device {
            ShapePropertiesSection {
                Menu {
                    DeviceMenuContent(
                        onSelectCategory: { selectAbstractDeviceOnSelection($0) },
                        onSelectFrame: { selectRealFrameOnSelection($0) }
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone")
                        Text("Change Device")
                    }
                }
                .menuStyle(.button)
                .fixedSize()
            }
        }

        if type == .text {
            let textShapes = shapes
            let primaryControlState = textShapes.first.flatMap(CustomFontRegistry.controlState(for:))
            let weightBinding = multiFontWeightBinding(controlState: primaryControlState)
            let italicBinding = multiItalicBinding(controlState: primaryControlState)

            ShapePropertiesSection {
                FontPicker(
                    selection: multiFontNameBinding(),
                    fontWeight: weightBinding,
                    italic: italicBinding,
                    customFaces: state.customFaces,
                    onApplyImportedSelection: { applyImportedFontSelectionOnSelection($0) },
                    onImportFont: { url in state.importCustomFont(from: url) }
                )

                ShapePropertiesSeparator()

                if showsMultiFontWeightPicker(primary: primaryControlState, textShapes: textShapes) {
                    FontWeightPicker(
                        selection: weightBinding,
                        options: primaryControlState?.availableWeights ?? [300, 400, 500, 700]
                    )

                    ShapePropertiesSeparator()
                }

                TextAlignPicker(selection: multiShapeOptionalBinding(\.textAlign, default: .center))
                    .frame(width: 90)
            }

            ShapePropertiesSection {
                if showsMultiItalicToggle(textShapes: textShapes) {
                    Toggle("Italic", isOn: italicBinding)
                        .toggleStyle(.switch)
                        .compactControlSize()
                }

                Toggle("Uppercase", isOn: multiShapeOptionalBinding(\.uppercase, default: false))
                    .toggleStyle(.switch)
                    .compactControlSize()
            }

        }

        if type == .rectangle || type == .image {
            ShapeCornerRadiusSection(value: multiShapeBinding(\.borderRadius))
        }

        if type == .star {
            ShapeStarPointsSection(
                pointCount: multiShapeOptionalBinding(\.starPointCount, default: CanvasShapeModel.defaultStarPointCount)
            )
        }

        if type == .svg {
            ShapePropertiesSection {
                Toggle("Custom color", isOn: multiShapeOptionalBinding(\.svgUseColor, default: false))
                    .toggleStyle(.switch)
                    .compactControlSize()
            }
        }

        if type.supportsOutline {
            ShapePropertiesSection {
                multiOutlineControls(shapes: shapes)
            }
        }

        ShapeShadowControls(
            shadow: multiShadowBinding(),
            showsOverrideDot: shapes.contains { $0.shadow?.isActive == true }
        )
    }

    @ViewBuilder
    private func multiOutlineControls(shapes: [CanvasShapeModel]) -> some View {
        let hasOutline = shapes.contains { ($0.outlineWidth ?? 0) > 0 }

        Toggle("Outline", isOn: Binding(
            get: { hasOutline },
            set: { setOutlineOnSelection($0) }
        ))
        .toggleStyle(.switch)
        .compactControlSize()

        if hasOutline {
            ColorPicker("", selection: multiShapeOptionalBinding(\.outlineColor, default: CanvasShapeModel.defaultOutlineColor), supportsOpacity: false)
                .labelsHidden()
                .frame(width: UIMetrics.ColorSwatch.inline)
                .padding(.horizontal, 4)
                .help("Outline")
                .accessibilityLabel("Outline")

            ShapePropertiesSeparator()

            ShapePropertiesControlGroup("Width") {
                Slider(value: multiShapeOptionalBinding(\.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth, continuous: true), in: 1...50)
                    .frame(width: UIMetrics.SliderWidth.standard)
            }
        }
    }
}
