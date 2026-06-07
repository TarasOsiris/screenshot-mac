import SwiftUI

/// Label + slider + numeric readout row shared by the device popovers
/// (`DeviceShadowPopover`, `Device3DAppearancePopover`): dense column layout
/// on macOS, touch-sized Form row on iPad.
struct PopoverSliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let displayValue: String

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
            Text(displayValue)
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
