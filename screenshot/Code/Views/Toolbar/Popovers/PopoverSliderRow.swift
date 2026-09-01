import SwiftUI

/// Label + slider + numeric readout row shared by the property popovers
/// (`ShadowPopover`, `Device3DAppearancePopover`): dense column layout
/// on macOS, touch-sized Form row on iPad.
///
/// The readout is derived here, from the binding, rather than handed down as a formatted string:
/// a slider drag runs at ~30 Hz, and computing the string in the parent made the parent read the
/// value — so every tick re-evaluated the whole popover, including its segmented `Picker`'s
/// `updateNSView` and AppKit layout. Formatting inside each row keeps the tick on the rows.
struct PopoverSliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// Rounded whole number — what almost every caller wants.
    var format: (Double) -> String = { "\(Int($0.rounded()))" }

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
