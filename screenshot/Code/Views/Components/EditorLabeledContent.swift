import SwiftUI

/// Native label/value layout for editor controls, with the label optically centered against
/// macOS control chrome. Keeping `LabeledContent` as the container preserves Form column sizing.
struct EditorLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            content
        } label: {
            label.offset(y: UIMetrics.LabeledControl.labelVerticalOffset)
        }
    }
}

extension EditorLabeledContent where Label == Text {
    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) {
            Text(label)
        }
    }
}
