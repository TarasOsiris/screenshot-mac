import SwiftUI

/// Label/value row for editor controls.
///
/// In the macOS inspector's grouped Form (`\.centersEditorLabels`), the label takes the content's
/// measured height and centers in it: that Form aligns field rows by top edge and slider rows by
/// baseline, and only a matched height suits both. Elsewhere the measurement must not run — in the
/// iPhone properties bar's scrolling strip it fed back into its own layout and hung the app.
struct EditorLabeledContent<Label: View, Content: View>: View {
    private let label: Label
    private let content: Content
    @Environment(\.centersEditorLabels) private var centersLabels
    @State private var contentHeight: CGFloat?

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.content = content()
        self.label = label()
    }

    var body: some View {
        if centersLabels {
            LabeledContent {
                HStack(spacing: 0) { content }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    .baselinesAtCenter()
            } label: {
                label
                    .frame(height: contentHeight, alignment: .center)
                    .baselinesAtCenter()
            }
        } else {
            LabeledContent {
                content
            } label: {
                label.offset(y: Self.stripLabelOffset)
            }
        }
    }

    /// AppKit fields render their text below the label's native baseline in compact rows.
    #if os(macOS)
    private static var stripLabelOffset: CGFloat { 4 }
    #else
    private static var stripLabelOffset: CGFloat { 0 }
    #endif
}

extension EditorLabeledContent where Label == Text {
    init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(content: content) {
            Text(label)
        }
    }
}

extension EnvironmentValues {
    /// Set by the macOS inspector's form; see `EditorLabeledContent`.
    @Entry var centersEditorLabels = false
}

private extension View {
    func baselinesAtCenter() -> some View {
        alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
            .alignmentGuide(.lastTextBaseline) { $0[VerticalAlignment.center] }
    }
}
