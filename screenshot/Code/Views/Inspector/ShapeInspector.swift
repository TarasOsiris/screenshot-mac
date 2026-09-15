#if os(macOS)
import SwiftUI

/// The selection inspector for one shape: the properties bar's controls, laid out as collapsible
/// sidebar sections.
///
/// `body` reads only `documentShape`, never `editingShape`: a slider tick must re-render the one
/// control it drives, not every section. Conditions that decide which rows exist read the
/// document's value for the same reason — none of them change mid-burst.
struct ShapeInspector: View, ShapeEditing {
    @Bindable var state: AppState
    let shapeId: UUID

    // Not `private`: ShapeInspector+Sections reads these.
    @State var isReplacingSvg = false
    @State var isReplacingFillImage = false
    @State var isLocalizationPopoverPresented = false

    @AppStorage("inspectorShapeGeometryExpanded") var isGeometryExpanded = true
    @AppStorage("inspectorShapeDeviceExpanded") var isDeviceExpanded = true
    @AppStorage("inspectorShape3DExpanded") var is3DExpanded = false
    @AppStorage("inspectorShapeTextExpanded") var isTextExpanded = true
    @AppStorage("inspectorShapeTextBackgroundExpanded") var isTextBackgroundExpanded = false
    @AppStorage("inspectorShapeMediaExpanded") var isMediaExpanded = true
    @AppStorage("inspectorShapeAppearanceExpanded") var isAppearanceExpanded = true
    @AppStorage("inspectorShapeFillExpanded") var isFillExpanded = true
    @AppStorage("inspectorShapeOutlineExpanded") var isOutlineExpanded = true
    @AppStorage("inspectorShapeShadowExpanded") var isShadowExpanded = true
    @AppStorage("inspectorShapeLocalizationExpanded") var isLocalizationExpanded = true

    var body: some View {
        if let i = idx(for: shapeId) {
            let shape = documentShape(at: i.row, shapeIdx: i.shape)
            let row = state.rows[i.row]

            VStack(spacing: 0) {
                InspectorBreadcrumb(
                    row: row,
                    icon: shape.type.icon,
                    title: shape.type.label,
                    onSelectRow: { state.selectRow(row.id) }
                ) {
                    ShapeSelectionActionButtons(
                        canBringToFront: canBringToFront(shapeId),
                        canSendToBack: canSendToBack(shapeId),
                        onBringToFront: { state.bringSelectedShapesToFront() },
                        onSendToBack: { state.sendSelectedShapesToBack() },
                        onDuplicate: { state.duplicateSelectedShapes() },
                        onDelete: { state.deleteShape(shapeId) }
                    )
                }
                Divider()

                Form {
                    if hasLocaleOverride(shapeId) {
                        LocaleOverrideIndicator {
                            state.resetLocaleOverride(shapeId: shapeId)
                        }
                    }
                    geometrySection(shape: shape)
                    typeSections(shape: shape)
                    appearanceSection(shape: shape)
                    fillSection(shape: shape)
                    outlineSection(shape: shape)
                    shadowSection
                    localizationSection(shape: shape)
                }
                .formStyle(.grouped)
                .scaledFont(UIMetrics.FontSize.body)
                .controlSize(.small)
            }
            .shapeReplacementPresenters(
                state: state,
                shapeId: shapeId,
                fallbackShape: shape,
                isReplacingSvg: $isReplacingSvg,
                isReplacingFillImage: $isReplacingFillImage
            )
            .onChange(of: shapeId) { _, _ in
                isLocalizationPopoverPresented = false
            }
        }
    }
}
#endif
