import SwiftUI

/// Label + slider + numeric readout row shared by the property popovers
/// (`ShadowPopover`, `Device3DAppearancePopover`) and the selection inspector: dense column layout
/// on macOS, touch-sized Form row on iPad, or a `LabeledContent` form row.
///
/// The readout is derived here, from the binding, rather than handed down as a formatted string:
/// a slider drag runs at ~30 Hz, and computing the string in the parent made the parent read the
/// value — so every tick re-evaluated the whole popover, including its segmented `Picker`'s
/// `updateNSView` and AppKit layout. Formatting inside each row keeps the tick on the rows.
struct PopoverSliderRow<Value: BinaryFloatingPoint, Leading: View>: View where Value.Stride: BinaryFloatingPoint {
    let label: LocalizedStringKey
    @Binding var value: Value
    let range: ClosedRange<Value>
    var layout: InspectorValueLayout = .popoverColumn
    /// Rounded whole number — what almost every caller wants.
    var format: (Value) -> String = { "\(Int($0.rounded()))" }
    /// An affordance that comes and goes with the value (a reset button). It leads *inside* the
    /// row: the content is trailing-aligned, so anything that appears on the trailing side nudges
    /// the field sideways — and wrapping the whole row in an `HStack` to place it would drop the
    /// row out of the `Form`'s label column.
    @ViewBuilder let leading: () -> Leading

    init(
        label: LocalizedStringKey,
        value: Binding<Value>,
        range: ClosedRange<Value>,
        layout: InspectorValueLayout = .popoverColumn,
        format: @escaping (Value) -> String = { "\(Int($0.rounded()))" },
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.label = label
        self._value = value
        self.range = range
        self.layout = layout
        self.format = format
        self.leading = leading
    }

    var body: some View {
        switch layout {
        case .strip, .popoverColumn:
            HStack(spacing: layout.columnGap) {
                Text(label)
                    #if os(macOS)
                    .foregroundStyle(.secondary)
                    #endif
                    .frame(width: UIMetrics.PopoverRow.labelWidth, alignment: .leading)
                Slider(value: $value, in: range)
                    .controlSize(.regular)
                readout
            }
        case .formRow:
            EditorLabeledContent(label) {
                HStack(spacing: layout.columnGap) {
                    leading()
                    Slider(value: $value, in: range)
                        .inspectorSliderWidth(layout)
                    readout
                }
                .reservesInspectorUnitColumn(layout)
            }
        }
    }

    /// The form rows take the inspector's shared value width so their readouts line up with the
    /// Position/Size fields; the popover columns keep their own dense sizing.
    private var readout: some View {
        Text(format(value))
            #if os(macOS)
            .frame(width: layout.valueWidth(strip: UIMetrics.PopoverRow.readoutWidth), alignment: .trailing)
            #else
            .frame(minWidth: layout.valueWidth(strip: UIMetrics.PopoverRow.readoutWidth), alignment: .trailing)
            #endif
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

extension PopoverSliderRow where Leading == EmptyView {
    init(
        label: LocalizedStringKey,
        value: Binding<Value>,
        range: ClosedRange<Value>,
        layout: InspectorValueLayout = .popoverColumn,
        format: @escaping (Value) -> String = { "\(Int($0.rounded()))" }
    ) {
        self.init(label: label, value: value, range: range, layout: layout, format: format) { EmptyView() }
    }
}
