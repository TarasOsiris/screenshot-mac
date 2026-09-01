import SwiftUI

/// Label + slider + numeric readout row shared by the property popovers
/// (`ShadowPopover`, `Device3DAppearancePopover`): dense column layout
/// on macOS, touch-sized Form row on iPad.
///
/// The readout is derived here, from the binding, rather than handed down as a formatted string:
/// a slider drag runs at ~30 Hz, and computing the string in the parent made the parent read the
/// value — so every tick re-evaluated the whole popover, including its segmented `Picker`'s
/// `updateNSView`. Formatting inside this row keeps the tick scoped to the row being dragged.
struct PopoverSliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    /// Rounded whole number — what almost every caller wants.
    init(label: LocalizedStringKey, value: Binding<Double>, range: ClosedRange<Double>,
         format: @escaping (Double) -> String = { "\(Int($0.rounded()))" }) {
        self.label = label
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
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
            Text(format(value))
                #if os(macOS)
                .frame(width: 44, alignment: .trailing)
                #else
                .frame(minWidth: 52, alignment: .trailing)
                #endif
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
