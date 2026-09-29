import SwiftUI

/// Label/value row. The label takes the content's height and centers in it: the grouped Form
/// aligns field rows by top edge and slider rows by baseline, and only a matched height suits both.
struct EditorLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content
    @State private var contentHeight: CGFloat?

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 0) { content }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                .baselinesAtCenter()
        } label: {
            label
                .frame(height: contentHeight, alignment: .center)
                .baselinesAtCenter()
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

private extension View {
    func baselinesAtCenter() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] }
    }
}
