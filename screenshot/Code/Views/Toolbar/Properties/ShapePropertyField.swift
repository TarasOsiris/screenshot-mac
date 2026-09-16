import SwiftUI

/// A numeric text field in the properties bar, bound to one property of the selected shape.
///
/// The four of these (font size, line height, opacity, rotation) each had their own ~30-line copy
/// of the same eight-modifier protocol, and both bugs this pattern has produced had to be fixed
/// four times: committing to a captured `shapeId` after the selection moved on, and re-applying a
/// no-op value (which flattens mixed per-run rich-text styling). Both fixes live here now.
struct ShapePropertyField: View {
    enum Keyboard { case integer, signed }

    let shapeId: UUID
    @Binding var text: String
    @Binding var isActive: Bool
    @FocusState private var isFocused: Bool

    let width: CGFloat
    /// Which surface this is drawing into — the wash's inset is the only thing that reads it.
    var layout: InspectorValueLayout = .strip
    var keyboard: Keyboard = .integer
    /// Opacity and rotation drop focus when the selection changes; the text fields don't, because
    /// they sit next to a preset menu the user may still be driving.
    var clearsFocusOnSelectionChange = false

    /// The model value this field mirrors. While the field is idle, a change here re-reads the
    /// displayed text — that's how a slider or a drag keeps the number in sync.
    let modelValue: Double?

    /// Renders the display string for a shape.
    let current: (UUID) -> String
    /// Writes the parsed value, or restores the display string when it doesn't parse.
    /// `nil` means "the selection is gone" and the caller decides what that does.
    let commit: (UUID?) -> Void
    /// Applies each keystroke as a continuous (coalesced-undo) edit. Only the text fields want
    /// this; opacity and rotation commit on submit or focus loss.
    var liveApply: (() -> Void)?
    /// The live selection, so a commit lands on what the user is looking at rather than on
    /// whatever `shapeId` was captured when this closure was built.
    let liveSelection: () -> UUID?
    /// The property this field writes, when the active locale can override it — opacity and
    /// rotation can't. Marked here rather than by the caller so the wash lands on the bezel and
    /// stops at it (how far that is inside the frame depends on the surface, hence
    /// `\.fieldBezelInset`): the composites around these fields put a preset chevron and a unit
    /// label in the same `HStack`, and neither is what the language overrides.
    var overrideField: LocaleOverrideField?

    var body: some View {
        let base = TextField("", text: $text, onEditingChanged: { editing in
            if editing {
                isActive = true
            } else {
                commit(liveSelection() ?? shapeId)
            }
        })
        .focused($isFocused)
        .frame(width: width)
        .textFieldStyle(.roundedBorder)
        .multilineTextAlignment(.center)
        .localeOverridden(overrideField, inset: layout.fieldBezelInset)

        keyboardApplied(base)
            .onAppear { text = current(shapeId) }
            .onChange(of: shapeId) { oldId, newId in
                // `oldId` is reliable where the captured `shapeId` is not, so flush the in-progress
                // edit to the shape it belongs to before rebinding.
                if isActive { commit(oldId) }
                text = current(newId)
                if clearsFocusOnSelectionChange { isFocused = false }
            }
            .onChange(of: modelValue) {
                guard !isActive else { return }
                let next = current(shapeId)
                if text != next { text = next }
            }
            .onChange(of: text) {
                guard isActive else { return }
                liveApply?()
            }
            .onSubmit { commit(liveSelection() ?? shapeId) }
    }

    @ViewBuilder
    private func keyboardApplied(_ view: some View) -> some View {
        switch keyboard {
        case .integer: view.integerKeyboard()
        case .signed: view.signedNumberKeyboard()
        }
    }
}
