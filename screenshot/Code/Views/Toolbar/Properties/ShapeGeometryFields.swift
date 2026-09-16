import SwiftUI

enum ShapeGeometryAxis: CaseIterable {
    case x, y, width, height

    var label: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .width: "W"
        case .height: "H"
        }
    }

    var overrideField: LocaleOverrideField {
        switch self {
        case .x: .positionX
        case .y: .positionY
        case .width: .width
        case .height: .height
        }
    }

    /// Spoken name for the field. The visible letter is notation VoiceOver would read as
    /// a bare "X", and Voice Control needs a phrase to match "click".
    var accessibilityLabel: LocalizedStringKey {
        switch self {
        case .x: "X position"
        case .y: "Y position"
        case .width: "Width"
        case .height: "Height"
        }
    }
}

/// X / Y / W / H for the selected shape: one strip in the properties bar, Position and Size form
/// rows in the inspector. The four drafts live together because every commit re-reads all of them.
struct ShapeGeometryFields: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    /// `formRow` emits two of them — Position and Size — into the caller's `Form`.
    let layout: InspectorValueLayout

    @State private var editingX = ""
    @State private var isXFieldActive = false
    @State private var editingY = ""
    @State private var isYFieldActive = false
    @State private var editingWidth = ""
    @State private var isWidthFieldActive = false
    @State private var editingHeight = ""
    @State private var isHeightFieldActive = false

    var body: some View {
        // Resolved once: each field would otherwise re-scan the document for the same frame.
        let placement = liveOrDocumentPlacement
        switch layout {
        case .strip, .popoverColumn:
            HStack(spacing: 6) {
                geometryField(.x, placement)
                geometryField(.y, placement)

                ShapePropertiesSeparator()

                geometryField(.width, placement)
                geometryField(.height, placement)
            }
        case .formRow:
            EditorLabeledContent("Position") {
                valueColumns(.x, .y, placement)
            }
            EditorLabeledContent("Size") {
                valueColumns(.width, .height, placement)
            }
        }
    }

    private func valueColumns(
        _ first: ShapeGeometryAxis,
        _ second: ShapeGeometryAxis,
        _ placement: CGRect?
    ) -> some View {
        HStack(spacing: layout.columnGap) {
            geometryField(first, placement)
            geometryField(second, placement)
        }
        .reservesInspectorUnitColumn(layout)
    }

    private func geometryField(_ axis: ShapeGeometryAxis, _ placement: CGRect?) -> some View {
        HStack(spacing: 3) {
            // Axis labels are notation, not prose — every design tool shows X/Y/W/H untranslated,
            // and the catalog's single-letter keys machine-translate to words ("Y" → "Oui").
            Text(verbatim: axis.label)
                .scaledFont(UIMetrics.FontSize.hint)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            ShapePropertyField(
                shapeId: shapeId,
                text: draft(axis).text,
                isActive: draft(axis).isActive,
                width: layout.valueWidth(strip: propertiesGeometryFieldWidth),
                layout: layout,
                keyboard: .signed,
                clearsFocusOnSelectionChange: true,
                modelValue: modelValue(axis, placement),
                current: { currentGeometryString(axis, for: $0) },
                commit: { commitGeometry(axis, to: $0, drafts: draft) },
                liveSelection: { state.selectedShapeId },
                overrideField: axis.overrideField
            )
            .accessibilityLabel(axis.accessibilityLabel)
        }
    }

    private func draft(_ axis: ShapeGeometryAxis) -> ShapeFieldDraft {
        switch axis {
        case .x: ShapeFieldDraft(text: $editingX, isActive: $isXFieldActive)
        case .y: ShapeFieldDraft(text: $editingY, isActive: $isYFieldActive)
        case .width: ShapeFieldDraft(text: $editingWidth, isActive: $isWidthFieldActive)
        case .height: ShapeFieldDraft(text: $editingHeight, isActive: $isHeightFieldActive)
        }
    }

    private func modelValue(_ axis: ShapeGeometryAxis, _ placement: CGRect?) -> Double? {
        guard let placement else { return nil }
        switch axis {
        case .x: return Double(placement.origin.x)
        case .y: return Double(placement.origin.y)
        case .width: return Double(placement.width)
        case .height: return Double(placement.height)
        }
    }

    /// `ShapePropertyField` re-reads its text when this moves, so it is what makes the fields
    /// follow a canvas gesture. Deliberately not `liveGeometryShape`: routing the trigger through
    /// the burst session would re-render the strip on every tick of an unrelated slider. Reads
    /// `placement(for:)` rather than `frame(for:)` for the same reason — these fields show no
    /// angle, so a rotate gesture must not reach them.
    private var liveOrDocumentPlacement: CGRect? {
        if let live = state.liveShapeGeometry.placement(for: shapeId) { return live }
        return resolvedDocumentShape(shapeId).map {
            CGRect(x: $0.x.rounded(), y: $0.y.rounded(), width: $0.width.rounded(), height: $0.height.rounded())
        }
    }
}

extension ShapeEditing {
    private func formatGeometry(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }

    private func parseGeometry(_ text: String) -> CGFloat? {
        text.localeTolerantDouble().map { CGFloat($0).rounded() }
    }

    /// `shape.x` is absolute across the row's whole template strip, so a shape on the third
    /// template would read ~3700. Field values are relative to the template the shape sits in.
    func currentGeometryString(_ axis: ShapeGeometryAxis, for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "0" }
        let shape = liveGeometryShape(shapeId, at: i)
        switch axis {
        case .x: return formatGeometry(shape.x - state.rows[i.row].templateOriginX(for: shape))
        case .y: return formatGeometry(shape.y)
        case .width: return formatGeometry(shape.width)
        case .height: return formatGeometry(shape.height)
        }
    }

    /// Bad input restores the display and a no-op writes nothing. Every exit re-reads *all four*
    /// fields, not just the one committed: an aspect lock rewrites the sibling dimension and a
    /// width change can move the shape into the next column, which shifts X's origin. A field left
    /// holding the stale value would write it back on its own blur and undo this edit.
    func commitGeometry(_ axis: ShapeGeometryAxis, to shapeId: UUID?, drafts: (ShapeGeometryAxis) -> ShapeFieldDraft) {
        drafts(axis).isActive.wrappedValue = false
        guard let shapeId, let i = idx(for: shapeId), var resolved = editingShape(shapeId) else { return }
        defer { refreshGeometryFields(for: shapeId, drafts: drafts) }
        guard let value = parseGeometry(drafts(axis).text.wrappedValue) else { return }

        let before = resolved
        applyGeometry(axis, value, to: &resolved, inRow: i.row)
        if resolved != before {
            state.updateShape(resolved)
        }
    }

    private func applyGeometry(_ axis: ShapeGeometryAxis, _ value: CGFloat, to shape: inout CanvasShapeModel, inRow rowIdx: Int) {
        switch axis {
        case .x: shape.x = value + state.rows[rowIdx].templateOriginX(for: shape)
        case .y: shape.y = value
        case .width: shape.applyManualWidth(value)
        case .height: shape.applyManualHeight(value)
        }
    }

    private func refreshGeometryFields(for shapeId: UUID, drafts: (ShapeGeometryAxis) -> ShapeFieldDraft) {
        for axis in ShapeGeometryAxis.allCases {
            let next = currentGeometryString(axis, for: shapeId)
            if drafts(axis).text.wrappedValue != next {
                drafts(axis).text.wrappedValue = next
            }
        }
    }
}
