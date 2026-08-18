import SwiftUI

/// Shared labeled popover trigger for the bottom properties bar: an icon + label + chevron
/// button that opens a `barPopover`. Unifies the Shadow / 3D / Text triggers so their icon,
/// chevron, and dropdown affordance stay consistent across macOS and iPad.
struct PropertiesBarPopoverTrigger<Label: View, Content: View>: View {
    let systemImage: String
    @Binding var isPresented: Bool
    var showsOverrideDot: Bool = false
    let help: LocalizedStringKey
    let popoverTitle: LocalizedStringKey
    var scrollableContent: Bool = false
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: UIMetrics.ActionButton.iconSize))
                label()
                    .font(.system(size: UIMetrics.FontSize.body))
                if showsOverrideDot { OverrideDot() }
                Image(systemName: "chevron.down")
                    .font(.system(size: UIMetrics.FontSize.hint, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .barPopover(isPresented: $isPresented, title: popoverTitle, scrollableContent: scrollableContent, content: content)
    }
}
