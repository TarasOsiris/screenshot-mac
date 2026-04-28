import SwiftUI

struct ShapePropertiesMultiSelectionBar: View {
    @Bindable var state: AppState

    private var rowIndex: Int? { state.selectedRowIndex }

    private var selectedShapes: [CanvasShapeModel] {
        guard let rowIndex else { return [] }
        let ids = state.selectedShapeIds
        return state.rows[rowIndex].shapes
            .filter { ids.contains($0.id) }
            .map { LocaleService.resolveShape($0, localeState: state.localeState) }
    }

    var body: some View {
        let shapes = selectedShapes
        let count = shapes.count
        let commonType = shapes.dropFirst().allSatisfy({ $0.type == shapes.first?.type }) ? shapes.first?.type : nil

        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        if let type = commonType {
                            Image(systemName: type.icon)
                                .font(.system(size: UIMetrics.FontSize.body, weight: .medium))
                        }
                        Text("\(count) shapes")
                            .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge))
                    )

                    if let commonType {
                        multiSelectionTypeControls(commonType, shapes: shapes)

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Opacity") {
                                Slider(value: multiShapeBinding(\.opacity), in: 0...1)
                                    .frame(width: UIMetrics.SliderWidth.standard)
                            }

                            ShapePropertiesSeparator()

                            ShapePropertiesControlGroup("Rotation") {
                                Slider(value: multiShapeBinding(\.rotation), in: 0...360)
                                    .frame(width: UIMetrics.SliderWidth.standard)
                            }
                        }

                        ShapePropertiesSection {
                            Toggle("Clip to Frame", isOn: multiShapeOptionalBinding(\.clipToTemplate, default: false))
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }

                    ShapeSelectionActionsSection(
                        canBringToFront: true,
                        canSendToBack: true,
                        onBringToFront: { state.bringSelectedShapesToFront() },
                        onSendToBack: { state.sendSelectedShapesToBack() },
                        onDuplicate: { state.duplicateSelectedShapes() },
                        onDelete: { state.deleteSelectedShapes() }
                    )
                }
                .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
                .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
            }

            Spacer(minLength: 0)

            ActionButton(icon: "xmark", tooltip: "Deselect all (Esc)", frameSize: 24) {
                state.selectedShapeIds = []
            }
            .padding(.trailing, 8)
        }
        .font(.system(size: UIMetrics.FontSize.body))
        .controlSize(.small)
        .background(.bar)
    }

    @ViewBuilder
    private func multiSelectionTypeControls(_ type: ShapeType, shapes: [CanvasShapeModel]) -> some View {
        if type == .device {
            ShapePropertiesSection {
                Menu {
                    DeviceMenuContent(
                        onSelectCategory: { category in
                            state.updateShapes(state.selectedShapeIds) {
                                let imageSize = category == .invisible
                                    ? $0.displayImageFileName.flatMap { state.screenshotImages[$0] }?.size
                                    : nil
                                $0.selectAbstractDevice(category, screenshotImageSize: imageSize)
                            }
                        },
                        onSelectFrame: { frame in
                            state.updateShapes(state.selectedShapeIds) { $0.selectRealFrame(frame) }
                        }
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
                    customFonts: state.customFonts,
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

                Picker("", selection: multiShapeOptionalBinding(\.textAlign, default: .center)) {
                    Image(systemName: "text.alignleft").tag(TextAlign.left)
                    Image(systemName: "text.aligncenter").tag(TextAlign.center)
                    Image(systemName: "text.alignright").tag(TextAlign.right)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
            }

            ShapePropertiesSection {
                if showsMultiItalicToggle(textShapes: textShapes) {
                    Toggle("Italic", isOn: italicBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                Toggle("Uppercase", isOn: multiShapeOptionalBinding(\.uppercase, default: false))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }

        if type == .rectangle || type == .image {
            ShapePropertiesSection {
                ShapePropertiesControlGroup("Radius") {
                    Slider(value: multiShapeBinding(\.borderRadius), in: 0...500)
                        .frame(width: UIMetrics.SliderWidth.standard)
                }
            }
        }

        if type == .star {
            ShapePropertiesSection {
                ShapePropertiesControlGroup("Points") {
                    Stepper(
                        value: multiShapeOptionalBinding(\.starPointCount, default: CanvasShapeModel.defaultStarPointCount),
                        in: 3...20
                    ) {
                        Text(verbatim: "\(shapes.first?.starPointCount ?? CanvasShapeModel.defaultStarPointCount)")
                            .frame(width: 20, alignment: .trailing)
                    }
                }
            }
        }

        if type == .svg {
            ShapePropertiesSection {
                Toggle("Custom color", isOn: multiShapeOptionalBinding(\.svgUseColor, default: false))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }

        if type.supportsOutline {
            ShapePropertiesSection {
                multiOutlineControls(shapes: shapes)
            }
        }
    }

    @ViewBuilder
    private func multiOutlineControls(shapes: [CanvasShapeModel]) -> some View {
        let hasOutline = shapes.contains { ($0.outlineWidth ?? 0) > 0 }

        Toggle("Outline", isOn: Binding(
            get: { hasOutline },
            set: { enabled in
                state.updateShapes(state.selectedShapeIds) { shape in
                    shape.outlineColor = enabled ? CanvasShapeModel.defaultOutlineColor : nil
                    shape.outlineWidth = enabled ? CanvasShapeModel.defaultOutlineWidth : nil
                }
            }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)

        if hasOutline {
            ColorPicker("", selection: multiShapeOptionalBinding(\.outlineColor, default: CanvasShapeModel.defaultOutlineColor), supportsOpacity: false)
                .labelsHidden()
                .frame(width: UIMetrics.ColorSwatch.inline)
                .padding(.horizontal, 4)

            ShapePropertiesSeparator()

            ShapePropertiesControlGroup("Width") {
                Slider(value: multiShapeOptionalBinding(\.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth), in: 1...50)
                    .frame(width: UIMetrics.SliderWidth.standard)
            }
        }
    }

    private var firstTextShape: CanvasShapeModel? {
        selectedShapes.first { $0.type == .text }
    }

    private func showsMultiFontWeightPicker(primary: CustomFontControlState?, textShapes: [CanvasShapeModel]) -> Bool {
        guard let primary else { return true }
        return primary.showsWeightPicker && textShapes.allSatisfy { shape in
            guard let state = CustomFontRegistry.controlState(for: shape) else { return true }
            return state.showsWeightPicker && state.availableWeights == primary.availableWeights
        }
    }

    private func showsMultiItalicToggle(textShapes: [CanvasShapeModel]) -> Bool {
        textShapes.allSatisfy { shape in
            CustomFontRegistry.controlState(for: shape)?.showsItalicToggle ?? true
        }
    }

    private func multiFontNameBinding() -> Binding<String> {
        Binding(
            get: { firstTextShape?.fontName ?? "" },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    shape.fontName = newValue
                    RichTextUtils.syncShapeStyleIfNeeded(in: &shape, property: .fontName)
                }
            }
        )
    }

    private func multiFontWeightBinding(controlState: CustomFontControlState?) -> Binding<Int> {
        Binding(
            get: {
                controlState?.effectiveWeight ?? firstTextShape?.fontWeight ?? 400
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    RichTextUtils.applyFontWeightUpdate(to: &shape, weight: newValue)
                }
            }
        )
    }

    private func multiItalicBinding(controlState: CustomFontControlState?) -> Binding<Bool> {
        Binding(
            get: {
                controlState?.effectiveItalic ?? firstTextShape?.italic ?? false
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    RichTextUtils.applyItalicUpdate(to: &shape, italic: newValue)
                }
            }
        )
    }

    private func multiShapeBinding<T: Equatable & Sendable>(_ keyPath: WritableKeyPath<CanvasShapeModel, T>) -> Binding<T> {
        Binding(
            get: {
                guard let rowIndex,
                      let first = state.rows[rowIndex].shapes.first(where: { state.selectedShapeIds.contains($0.id) })
                else { return CanvasShapeModel.placeholder[keyPath: keyPath] }
                return LocaleService.resolveShape(first, localeState: state.localeState)[keyPath: keyPath]
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    shape[keyPath: keyPath] = newValue
                }
            }
        )
    }

    private func multiShapeOptionalBinding<T: Equatable & Sendable>(_ keyPath: WritableKeyPath<CanvasShapeModel, T?>, default defaultValue: T) -> Binding<T> {
        Binding(
            get: {
                guard let rowIndex,
                      let first = state.rows[rowIndex].shapes.first(where: { state.selectedShapeIds.contains($0.id) })
                else { return defaultValue }
                return LocaleService.resolveShape(first, localeState: state.localeState)[keyPath: keyPath] ?? defaultValue
            },
            set: { newValue in
                state.updateShapes(state.selectedShapeIds) { shape in
                    shape[keyPath: keyPath] = newValue
                }
            }
        )
    }
}
