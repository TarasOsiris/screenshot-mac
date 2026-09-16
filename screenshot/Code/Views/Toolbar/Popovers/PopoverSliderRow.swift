import SwiftUI

/// Label + slider + numeric readout row shared by the property popovers
/// (`ShadowPopover`, `Device3DAppearancePopover`) and the selection inspector: dense column layout
/// on macOS, touch-sized Form row on iPad, or a `LabeledContent` form row.
///
/// The readout is derived here, from the binding, rather than handed down as a formatted string:
/// a slider drag runs at ~30 Hz, and computing the string in the parent made the parent read the
/// value — so every tick re-evaluated the whole popover, including its segmented `Picker`'s
/// `updateNSView` and AppKit layout. Formatting inside each row keeps the tick on the rows.
struct PopoverSliderRow<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    enum Layout { case column, form }

    let label: LocalizedStringKey
    @Binding var value: Value
    let range: ClosedRange<Value>
    var layout: Layout = .column
    /// Shown in the form row's unit column, so it can't sit inside the value column where it
    /// would never line up. Baking it into `format` is what made the multi-selection rows ragged.
    var unit: String?
    /// Rounded whole number — what almost every caller wants.
    var format: (Value) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        switch layout {
        case .column:
            HStack(spacing: 8) {
                #if os(macOS)
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                #else
                Text(label)
                    .frame(width: 80, alignment: .leading)
                #endif
                Slider(value: $value, in: range)
                    .controlSize(.regular)
                readout
            }
        case .form:
            InspectorValueRow(label: label, unit: unit) {
                InspectorSliderValue(value: $value, range: range, format: format)
            }
        }
    }

    private var readout: some View { readout(width: nil) }

    /// The popover columns keep their own dense sizing; a form row's readout is sized by
    /// `InspectorSliderValue`, which owns the inspector's shared column.
    private func readout(width: CGFloat?) -> some View {
        Text(format(value))
            #if os(macOS)
            .frame(width: width ?? 44, alignment: .trailing)
            #else
            .frame(minWidth: width ?? 52, alignment: .trailing)
            #endif
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

/// The slider and readout of an inspector form row, without the row around them — so a row that
/// needs something else in its value area (the multi-selection rotation reset) composes the same
/// control instead of rebuilding it.
struct InspectorSliderValue<Value: BinaryFloatingPoint>: View where Value.Stride: BinaryFloatingPoint {
    @Binding var value: Value
    let range: ClosedRange<Value>
    var format: (Value) -> String = { "\(Int($0.rounded()))" }

    var body: some View {
        HStack(spacing: InspectorValueLayout.formRow.columnGap) {
            Slider(value: $value, in: range)
                .inspectorSliderWidth(.formRow)

            Text(format(value))
                .frame(width: UIMetrics.InspectorRow.valueWidth, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
