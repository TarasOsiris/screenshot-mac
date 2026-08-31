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

struct ShapePropertiesSingleSelectionBar: View {
    static let defaultFontSize: CGFloat = CanvasShapeModel.defaultFontSize
    static let fontSizeRange: ClosedRange<CGFloat> = 8...400
    static let fontSizePresets: [Int] = CanvasShapeModel.fontSizePresets
    @Bindable var state: AppState
    // Not `private`: the +Sections extension file reads these.
    @State var isReplacingSvg = false
    #if os(macOS)
    @State var isReplacingFillImage = false
    #endif
    @State var isFillPopoverPresented = false
    @State var isTextPopoverPresented = false
    @State var isTextLocalizationPopoverPresented = false
    @State var isTextBackgroundPopoverPresented = false
    @State var editingFontSize: String = ""
    @State var isFontSizeFieldActive = false
    @State var editingLineHeight: String = ""
    @State var isLineHeightFieldActive = false
    @State var editingOpacity: String = ""
    @State var isOpacityFieldActive = false
    @State var editingRotation: String = ""
    @State var isRotationFieldActive = false
    @State var editingX: String = ""
    @State var isXFieldActive = false
    @State var editingY: String = ""
    @State var isYFieldActive = false
    @State var editingWidth: String = ""
    @State var isWidthFieldActive = false
    @State var editingHeight: String = ""
    @State var isHeightFieldActive = false
    @FocusState var focusedField: Field?
    enum Field: Hashable { case opacity, fontSize, lineHeight, rotation, x, y, width, height }
    static let lineHeightPresets: [Int] = [50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 175, 200]

    var rowIndex: Int? { state.selectedRowIndex }
    var shapeIndex: Int? {
        guard let rowIndex, let shapeId = state.selectedShapeId else { return nil }
        return state.rows[rowIndex].shapes.firstIndex { $0.id == shapeId }
    }
    var canBringToFront: Bool {
        guard let rowIndex, let shapeIndex else { return false }
        return shapeIndex < state.rows[rowIndex].shapes.count - 1
    }
    var canSendToBack: Bool {
        guard let shapeIndex else { return false }
        return shapeIndex > 0
    }

    /// macOS only: iPad routes image selection through `ImageSourceMenu` via `onImageSelected`.
    func pickAndReplaceImage(for shapeId: UUID) {
        guard let image = FilePicker.pickImage() else { return }
        state.saveImage(image, for: shapeId, source: .panel)
    }

    func idx(for shapeId: UUID) -> (row: Int, shape: Int)? {
        guard let ri = rowIndex, ri < state.rows.count,
              let si = state.rows[ri].shapes.firstIndex(where: { $0.id == shapeId })
        else { return nil }
        return (ri, si)
    }

    /// The selected shape with locale overrides applied (for display).
    func resolvedShape(at rowIndex: Int, shapeIdx: Int) -> CanvasShapeModel {
        let base = state.rows[rowIndex].shapes[shapeIdx]
        return LocaleService.resolveShape(base, localeState: state.localeState)
    }

    /// Resolves a shape by id at call time. Popover content that the iPad docked panel keeps
    /// across updates must read through this instead of capturing a shape value.
    func liveShape(_ shapeId: UUID) -> CanvasShapeModel? {
        idx(for: shapeId).map { resolvedShape(at: $0.row, shapeIdx: $0.shape) }
    }

    /// Whether the selected shape has any locale override for the active locale.
    var hasLocaleOverride: Bool {
        guard let shapeId = state.selectedShapeId, !state.localeState.isBaseLocale else { return false }
        return state.shapeHasActiveLocaleOverride(shapeId)
    }

    /// Whether a shape has a locale image override for the active locale.
    func hasLocaleImageOverride(_ shapeId: UUID) -> Bool {
        guard !state.localeState.isBaseLocale else { return false }
        return state.localeState.override(forCode: state.localeState.activeLocaleCode, shapeId: shapeId)?.overrideImageFileName != nil
    }

    var body: some View {
        if let rowIndex, let shapeIdx = shapeIndex {
            let shape = resolvedShape(at: rowIndex, shapeIdx: shapeIdx)
            let shapeId = shape.id

            HStack(spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ShapePropertiesBadge(type: shape.type)

                        geometrySection(shape: shape, shapeId: shapeId)

                        deviceSections(shape: shape, shapeId: shapeId)

                        ShapeShadowControls(
                            shadow: optionalConfigBinding(shapeId, \.shadow, fallback: ShadowConfig(), isEmpty: \.isEmpty)
                        )

                        fillSection(shape: shape, shapeId: shapeId)

                        ShapeOpacitySection(
                            shapeId: shapeId,
                            field: .opacity,
                            opacity: shape.opacity,
                            text: $editingOpacity,
                            isActive: $isOpacityFieldActive,
                            focus: $focusedField,
                            current: { currentOpacityString(for: $0) },
                            commit: { commitOpacity(to: $0) },
                            liveSelection: { state.selectedShapeId }
                        )

                        ShapeRotationSection(
                            shapeId: shapeId,
                            field: .rotation,
                            slider: shapeBinding(shapeId, \.rotation, continuous: true),
                            text: $editingRotation,
                            isActive: $isRotationFieldActive,
                            focus: $focusedField,
                            current: { currentRotationString(for: $0) },
                            commit: { commitRotation(to: $0) },
                            liveSelection: { state.selectedShapeId },
                            onReset: { resetRotation(shapeId: shapeId) }
                        )

                        shapeGeometrySections(shape: shape, shapeId: shapeId)

                        mediaSections(shape: shape, shapeId: shapeId)

                        if !state.localeState.isBaseLocale && hasLocaleOverride {
                            LocaleOverrideIndicator {
                                state.resetLocaleOverride(shapeId: shapeId)
                            }
                        }

                        textSections(shape: shape, shapeId: shapeId)

                        ShapeClipToFrameSection(
                            clipToTemplate: shapeBinding(shapeId, \.clipToTemplate, default: false)
                        )

                        ShapeSelectionActionsSection(
                            canBringToFront: canBringToFront,
                            canSendToBack: canSendToBack,
                            onBringToFront: { state.bringSelectedShapesToFront() },
                            onSendToBack: { state.sendSelectedShapesToBack() },
                            onDuplicate: { state.duplicateSelectedShapes() },
                            onDelete: { state.deleteShape(shapeId) }
                        )
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
            .modifier(PropertiesBarChrome())
            // macOS-only: the fill swatch's "pick image" opens this file panel. iPad picks the
            // fill image through ImageSourceMenu inside BackgroundImageEditor (→ saveShapeFillImage).
            #if os(macOS)
            .imageSourcePicker(isPresented: $isReplacingFillImage) { image in
                state.saveShapeFillImage(image, for: shapeId)
            }
            #endif
            .sheet(isPresented: $isReplacingSvg) {
                SvgPasteDialog(isPresented: $isReplacingSvg) { svgContent, _, useColor, color in
                    replaceSvg(for: shapeId, content: svgContent, useColor: useColor, color: color)
                }
            }
        }
    }
}
