import SwiftUI

#if os(macOS)
struct ShortcutRow: View {
    let keys: String
    let description: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(keys)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Color.primary.opacity(UIMetrics.Opacity.sectionFill),
                    in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                )
                .frame(minWidth: 160, alignment: .leading)
            Text(description)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
#endif
