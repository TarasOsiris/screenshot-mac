import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    enum GeometryAxis: CaseIterable {
        case x, y, width, height

        var label: String {
            switch self {
            case .x: "X"
            case .y: "Y"
            case .width: "W"
            case .height: "H"
            }
        }

        var field: Field {
            switch self {
            case .x: .x
            case .y: .y
            case .width: .width
            case .height: .height
            }
        }
    }

    func geometrySection(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        ShapePropertiesSection {
            geometryField(.x, shape: shape, shapeId: shapeId)
            geometryField(.y, shape: shape, shapeId: shapeId)

            ShapePropertiesSeparator()

            geometryField(.width, shape: shape, shapeId: shapeId)
            geometryField(.height, shape: shape, shapeId: shapeId)
        }
    }

    private func geometryField(_ axis: GeometryAxis, shape: CanvasShapeModel, shapeId: UUID) -> some View {
        HStack(spacing: 3) {
            // Axis labels are notation, not prose — every design tool shows X/Y/W/H untranslated,
            // and the catalog's single-letter keys machine-translate to words ("Y" → "Oui").
            Text(verbatim: axis.label)
                .scaledFont(UIMetrics.FontSize.hint)
                .foregroundStyle(.secondary)

            ShapePropertyField(
                shapeId: shapeId,
                field: axis.field,
                text: editingText(axis),
                isActive: isFieldActive(axis),
                focus: $focusedField,
                width: propertiesGeometryFieldWidth,
                keyboard: .signed,
                clearsFocusOnSelectionChange: true,
                modelValue: modelValue(axis, of: shape),
                current: { currentGeometryString(axis, for: $0) },
                commit: { commitGeometry(axis, to: $0) },
                liveSelection: { state.selectedShapeId }
            )
        }
    }

    // MARK: - Field state

    private func editingText(_ axis: GeometryAxis) -> Binding<String> {
        switch axis {
        case .x: $editingX
        case .y: $editingY
        case .width: $editingWidth
        case .height: $editingHeight
        }
    }

    private func isFieldActive(_ axis: GeometryAxis) -> Binding<Bool> {
        switch axis {
        case .x: $isXFieldActive
        case .y: $isYFieldActive
        case .width: $isWidthFieldActive
        case .height: $isHeightFieldActive
        }
    }

    // MARK: - Values

    private func modelValue(_ axis: GeometryAxis, of shape: CanvasShapeModel) -> Double {
        switch axis {
        case .x: Double(shape.x)
        case .y: Double(shape.y)
        case .width: Double(shape.width)
        case .height: Double(shape.height)
        }
    }

    private func formatGeometry(_ value: CGFloat) -> String {
        "\(Int(value.rounded()))"
    }

    private func parseGeometry(_ text: String) -> CGFloat? {
        text.localeTolerantDouble().map { CGFloat($0).rounded() }
    }

    /// `shape.x` is absolute across the row's whole template strip, so a shape on the third
    /// template would read ~3700. Field values are relative to the template the shape sits in.
    func currentGeometryString(_ axis: GeometryAxis, for shapeId: UUID) -> String {
        guard let i = idx(for: shapeId) else { return "0" }
        let shape = resolvedShape(at: i.row, shapeIdx: i.shape)
        switch axis {
        case .x: return formatGeometry(shape.x - state.rows[i.row].templateOriginX(for: shape))
        case .y: return formatGeometry(shape.y)
        case .width: return formatGeometry(shape.width)
        case .height: return formatGeometry(shape.height)
        }
    }

    // MARK: - Commit

    /// Bad input restores the display and a no-op writes nothing. Every exit re-reads *all four*
    /// fields, not just the one committed: an aspect lock rewrites the sibling dimension and a
    /// width change can move the shape into the next column, which shifts X's origin. A field left
    /// holding the stale value would write it back on its own blur and undo this edit.
    func commitGeometry(_ axis: GeometryAxis, to shapeId: UUID?) {
        isFieldActive(axis).wrappedValue = false
        guard let shapeId, let i = idx(for: shapeId) else { return }
        defer { refreshGeometryFields(for: shapeId) }
        guard let value = parseGeometry(editingText(axis).wrappedValue) else { return }

        var resolved = resolvedShape(at: i.row, shapeIdx: i.shape)
        let before = resolved
        apply(axis, value, to: &resolved, inRow: i.row)
        if resolved != before {
            state.updateShape(resolved)
        }
    }

    private func apply(_ axis: GeometryAxis, _ value: CGFloat, to shape: inout CanvasShapeModel, inRow rowIdx: Int) {
        switch axis {
        case .x: shape.x = value + state.rows[rowIdx].templateOriginX(for: shape)
        case .y: shape.y = value
        case .width: shape.applyManualWidth(value)
        case .height: shape.applyManualHeight(value)
        }
    }

    private func refreshGeometryFields(for shapeId: UUID) {
        for axis in GeometryAxis.allCases {
            let next = currentGeometryString(axis, for: shapeId)
            if editingText(axis).wrappedValue != next {
                editingText(axis).wrappedValue = next
            }
        }
    }
}
