#if os(macOS)
import SwiftUI

/// The selection inspector for several shapes. Writes fan out to the whole selection and each
/// control shows the first shape's value, as in the properties bar. Unlike the bar, opacity,
/// rotation, clipping and shadow stay available for a mixed-type selection — every type has them.
struct MultiShapeInspector: View, MultiShapeEditing {
    @Bindable var state: AppState

    var body: some View {
        let shapes = selectedShapes
        if let row = state.selectedRow, shapes.count > 1 {
            let commonType = commonShapeType(of: shapes)
            let overriddenIds = state.overriddenShapeIds(in: row).intersection(state.selectedShapeIds)

            VStack(spacing: 0) {
                InspectorBreadcrumb(
                    row: row,
                    icon: commonType?.icon ?? "square.on.square",
                    title: String(localized: "\(shapes.count) shapes"),
                    onSelectRow: { state.selectRow(row.id) },
                    overrideChip: overriddenIds.isEmpty ? nil : LocaleOverrideChip(
                        scope: .selection(ids: overriddenIds), state: state
                    )
                ) {
                    ShapeSelectionActionButtons(
                        onBringToFront: { state.bringSelectedShapesToFront() },
                        onSendToBack: { state.sendSelectedShapesToBack() },
                        onDuplicate: { state.duplicateSelectedShapes() },
                        onDelete: { state.deleteSelectedShapes() }
                    )
                }
                Divider()
                InspectorAlignmentBar(canDistribute: shapes.count >= 3) { state.alignSelectedShapes($0) }

                Form {
                    if let commonType {
                        typeSections(commonType, shapes: shapes)
                    }
                    appearanceSection(commonType: commonType, shapes: shapes)
                    outlineSection(commonType: commonType, shapes: shapes)
                    InspectorSection(.shapeShadow, "Shadow") {
                        ShadowControls(shadow: multiShadowBinding())
                    }
                }
                .inspectorFormChrome()
            }
        }
    }

    @ViewBuilder
    private func typeSections(_ type: ShapeType, shapes: [CanvasShapeModel]) -> some View {
        switch type {
        case .device:
            InspectorSection(.shapeDevice, "Device") {
                Menu {
                    DeviceMenuContent(
                        onSelectCategory: { selectAbstractDeviceOnSelection($0) },
                        onSelectFrame: { selectRealFrameOnSelection($0) }
                    )
                } label: {
                    Label("Change Device", systemImage: "iphone")
                }
                .menuStyle(.button)
            }
        case .text:
            textSection(shapes: shapes)
        case .rectangle, .circle, .star, .image, .svg:
            EmptyView()
        }
    }

    @ViewBuilder
    private func textSection(shapes: [CanvasShapeModel]) -> some View {
        let primaryControlState = shapes.first.flatMap(CustomFontRegistry.controlState(for:))
        let weightBinding = multiFontWeightBinding(controlState: primaryControlState)
        let italicBinding = multiItalicBinding(controlState: primaryControlState)

        InspectorSection(.shapeText, "Text") {
            EditorLabeledContent("Font") {
                FontPicker(
                    selection: multiFontNameBinding(),
                    fontWeight: weightBinding,
                    italic: italicBinding,
                    customFaces: state.customFaces,
                    onApplyImportedSelection: { applyImportedFontSelectionOnSelection($0) },
                    onImportFont: { url in state.importCustomFont(from: url) }
                )
            }

            if showsMultiFontWeightPicker(primary: primaryControlState, textShapes: shapes) {
                EditorLabeledContent("Weight") {
                    FontWeightPicker(
                        selection: weightBinding,
                        options: primaryControlState?.availableWeights ?? [300, 400, 500, 700]
                    )
                }
            }

            EditorLabeledContent("Align") {
                TextAlignPicker(selection: multiShapeOptionalBinding(\.textAlign, default: .center))
                    .fixedSize()
            }

            if showsMultiItalicToggle(textShapes: shapes) {
                Toggle("Italic", isOn: italicBinding)
                    .toggleStyle(.switch)
            }

            Toggle("Uppercase", isOn: multiShapeOptionalBinding(\.uppercase, default: false))
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private func appearanceSection(commonType: ShapeType?, shapes: [CanvasShapeModel]) -> some View {
        InspectorSection(.shapeAppearance, "Appearance") {
            PopoverSliderRow(label: "Opacity", value: multiShapeBinding(\.opacity), range: 0...1, layout: .form) {
                "\(Int(($0 * 100).rounded()))%"
            }

            HStack(spacing: 4) {
                PopoverSliderRow(label: "Rotation", value: multiShapeBinding(\.rotation), range: 0...360, layout: .form) {
                    "\(Int($0.rounded()))°"
                }
                if shapes.contains(where: { $0.rotation != 0 }) {
                    ActionButton(icon: "arrow.counterclockwise", tooltip: "Reset rotation", frameSize: UIMetrics.IconButton.frameSize) {
                        resetRotationOnSelection()
                    }
                }
            }

            if commonType == .rectangle || commonType == .image {
                PopoverSliderRow(label: "Radius", value: multiShapeBinding(\.borderRadius), range: 0...500, layout: .form)
            }

            if commonType == .star {
                EditorLabeledContent("Points") {
                    Stepper(
                        value: multiShapeOptionalBinding(\.starPointCount, default: CanvasShapeModel.defaultStarPointCount),
                        in: 3...20
                    ) {
                        Text(verbatim: "\(shapes.first?.starPointCount ?? CanvasShapeModel.defaultStarPointCount)")
                            .monospacedDigit()
                    }
                }
            }

            if commonType == .svg {
                Toggle("Custom color", isOn: multiShapeOptionalBinding(\.svgUseColor, default: false))
                    .toggleStyle(.switch)
            }

            Toggle("Clip to Frame", isOn: multiShapeOptionalBinding(\.clipToTemplate, default: false))
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private func outlineSection(commonType: ShapeType?, shapes: [CanvasShapeModel]) -> some View {
        if let commonType, commonType.supportsOutline {
            let hasOutline = shapes.contains { ($0.outlineWidth ?? 0) > 0 }
            InspectorSection(.shapeOutline, "Outline") {
                InspectorOutlineRows(
                    isOn: Binding(get: { hasOutline }, set: { setOutlineOnSelection($0) }),
                    color: multiShapeOptionalBinding(\.outlineColor, default: CanvasShapeModel.defaultOutlineColor),
                    width: multiShapeOptionalBinding(\.outlineWidth, default: CanvasShapeModel.defaultOutlineWidth, continuous: true),
                    showsDetails: hasOutline
                )
            }
        }
    }
}
#endif
