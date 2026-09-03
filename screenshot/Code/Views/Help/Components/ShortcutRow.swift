import SwiftUI

#if os(macOS)
struct ShortcutRow: View {
    let item: ShortcutRowItem
    @Environment(\.helpSearchQuery) private var query

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AttributedString(item.keys).helpHighlighting(query))
                .font(.system(.body, design: .monospaced).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Color.primary.opacity(UIMetrics.Opacity.sectionFill),
                    in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                )
                .frame(minWidth: 160, alignment: .leading)
            HelpText(item.description)
            Spacer(minLength: 0)
        }
    }
}
#endif
