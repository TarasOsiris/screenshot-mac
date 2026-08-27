import SwiftUI

/// A popover row pairing a slider with an editable integer field. The slider drives the
/// (continuous) binding live; the field reflects it when unfocused and commits typed input
/// on submit/blur. Double-clicking the label resets to `resetValue`.
struct PopoverSliderField: View {
    let label: LocalizedStringKey
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var resetValue: CGFloat = 0

    @State private var text = ""
    @FocusState private var focused: Bool

    private func sync() { text = "\(Int(value.rounded()))" }

    private func commit() {
        if let parsed = Double(text) {
            value = min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
        }
        sync()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 4) {
                Slider(value: $value, in: range)
                    .frame(width: UIMetrics.SliderWidth.standard)
                TextField("", text: $text)
                    .focused($focused)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: propertiesNumericFieldWidth)
                    .integerKeyboard()
                    .onSubmit { commit() }
                    .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            }
        } label: {
            Text(label)
                .onTapGesture(count: 2) { value = resetValue }
                #if os(macOS)
                .help("Double-click to reset")
                #else
                .help("Double-tap to reset")
                #endif
        }
        .onAppear { sync() }
        .onChange(of: value) { _, _ in if !focused { sync() } }
    }
}
