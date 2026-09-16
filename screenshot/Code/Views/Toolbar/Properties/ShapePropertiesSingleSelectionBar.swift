import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
let propertiesNumericFieldWidth: CGFloat = 44
let propertiesGeometryFieldWidth: CGFloat = 52
let propertiesOpacityFieldWidth: CGFloat = 40
let propertiesFontFieldWidth: CGFloat = 48
let propertiesTrackingValueWidth: CGFloat = 32
let propertiesSliderValueWidth: CGFloat = 28
let propertiesStepperValueWidth: CGFloat = 20
#else
let propertiesNumericFieldWidth: CGFloat = 56
let propertiesGeometryFieldWidth: CGFloat = 64
let propertiesOpacityFieldWidth: CGFloat = 52
let propertiesFontFieldWidth: CGFloat = 56
let propertiesTrackingValueWidth: CGFloat = 40
let propertiesSliderValueWidth: CGFloat = 36
let propertiesStepperValueWidth: CGFloat = 28
#endif

struct ShapePropertiesSingleSelectionBar: View, ShapeEditing {
    @Bindable var state: AppState
    // Not `private`: the +Sections extension file reads these.
    @State var isReplacingSvg = false
    @State var isReplacingFillImage = false
    @State var isFillPopoverPresented = false
    @State var isTextPopoverPresented = false
    @State var isTextLocalizationPopoverPresented = false
    @State var isTextBackgroundPopoverPresented = false

    var body: some View {
        if let shapeId = state.selectedShapeId, let i = idx(for: shapeId) {
            let shape = documentShape(at: i.row, shapeIdx: i.shape)
            let overrideFields = LocaleService.overriddenFields(
                for: state.rows[i.row].shapes[i.shape],
                localeCode: state.localeState.activeLocaleCode,
                localeState: state.localeState
            )

            HStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ShapePropertiesBadge(type: shape.type)

                        if !overrideFields.isEmpty {
                            LocaleOverrideChip(scope: .shape(id: shapeId, fields: overrideFields), state: state)
                        }

                        ShapePropertiesSection {
                            ShapeGeometryFields(state: state, shapeId: shapeId, shape: shape, layout: .strip)
                        }

                        deviceSections(shape: shape, shapeId: shapeId)

                        ShapeShadowControls(
                            shadow: optionalConfigBinding(shapeId, \.shadow, fallback: ShadowConfig(), isEmpty: \.isEmpty),
                            showsOverrideDot: shape.shadow?.isActive == true
                        )

                        fillSection(shape: shape, shapeId: shapeId)

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Opacity") {
                                ShapeOpacityField(state: state, shapeId: shapeId)
                            }
                        }

                        ShapePropertiesSection {
                            ShapePropertiesControlGroup("Rotation") {
                                ShapeRotationControl(state: state, shapeId: shapeId)
                            }
                        }

                        shapeGeometrySections(shape: shape, shapeId: shapeId)

                        mediaSections(shape: shape, shapeId: shapeId)

                        textSections(shape: shape, shapeId: shapeId)

                        ShapeClipToFrameSection(
                            clipToTemplate: shapeBinding(shapeId, \.clipToTemplate, default: false)
                        )

                        ShapePropertiesSection {
                            ShapeSelectionActionButtons(
                                canBringToFront: canBringToFront(shapeId),
                                canSendToBack: canSendToBack(shapeId),
                                onBringToFront: { state.bringSelectedShapesToFront() },
                                onSendToBack: { state.sendSelectedShapesToBack() },
                                onDuplicate: { state.duplicateSelectedShapes() },
                                onDelete: { state.deleteShape(shapeId) }
                            )
                        }
                    }
                    .padding(.horizontal, ShapePropertiesSectionLayout.horizontalPadding)
                    .padding(.vertical, ShapePropertiesSectionLayout.verticalPadding)
                }
                .scrollIndicators(.hidden)

                Spacer(minLength: 0)

                #if os(macOS)
                ActionButton(icon: "xmark", tooltip: "Deselect shape (Esc)", frameSize: UIMetrics.IconButton.frameSize) {
                    state.selectedShapeIds = []
                }
                .padding(.trailing, 8)
                #else
                ActionButton(icon: "xmark", tooltip: "Deselect shape", frameSize: UIMetrics.IconButton.frameSize) {
                    state.selectedShapeIds = []
                }
                .padding(.trailing, 8)
                #endif
            }
            .scaledFont(UIMetrics.FontSize.body)
            .compactControlSize()
            .denseBarTypography()
            .localeOverrideMarks(shapeId: shapeId, fields: overrideFields)
            .modifier(PropertiesBarChrome())
            .shapeReplacementPresenters(
                state: state,
                shapeId: shapeId,
                fallbackShape: shape,
                isReplacingSvg: $isReplacingSvg,
                isReplacingFillImage: $isReplacingFillImage
            )
        }
    }
}
