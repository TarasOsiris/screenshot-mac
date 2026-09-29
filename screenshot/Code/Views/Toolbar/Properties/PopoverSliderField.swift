import SwiftUI

/// A popover row pairing a slider with an editable integer field. The slider drives the
/// (continuous) binding live; the field reflects it when unfocused and commits typed input
/// on submit/blur. Double-clicking the label resets to `resetValue`.
struct PopoverSliderField: View {
    let label: LocalizedStringKey
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var resetValue: CGFloat = 0
    /// `.formRow` sizes the slider and field to the inspector's shared columns.
    var layout: InspectorValueLayout = .popoverColumn
    /// Form rows only: a suffix such as "%" in the inspector's unit column.
    var unit: String?

    @State private var text = ""
    @FocusState private var focused: Bool
    /// The binding as it was when editing began. A host that keeps this view alive across a selection
    /// change hands it the next shape's binding, and a blur-commit through that would move the draft.
    @State private var editingTarget: Binding<CGFloat>?

    private func sync() { text = "\(Int(value.rounded()))" }

    private func commit() {
        let target = editingTarget ?? $value
        editingTarget = nil
        if let parsed = Double(text) {
            target.wrappedValue = min(max(CGFloat(parsed), range.lowerBound), range.upperBound)
        }
        sync()
    }

    var body: some View {
        EditorLabeledContent {
            // The popover packs its pair tighter than the inspector's shared columns.
            HStack(spacing: layout == .formRow ? layout.columnGap : 4) {
                Slider(value: $value, in: range)
                    .inspectorSliderWidth(layout)
                if let unit {
                    field.unitSuffix(unit, layout)
                } else {
                    field.reservesInspectorUnitColumn(layout)
                }
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

    private var field: some View {
        TextField("", text: $text)
            .focused($focused)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(layout == .formRow ? .center : .trailing)
            .frame(width: layout == .formRow ? UIMetrics.InspectorRow.valueWidth : propertiesNumericFieldWidth)
            .integerKeyboard()
            .onSubmit { commit() }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    editingTarget = $value
                } else {
                    commit()
                }
            }
    }
}
