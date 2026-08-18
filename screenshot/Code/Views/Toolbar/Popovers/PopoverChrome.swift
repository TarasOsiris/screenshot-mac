import SwiftUI

/// Chrome shared by the bar popovers. `ShadowPopover` and `Device3DAppearancePopover` had
/// byte-identical section headers and the same title-plus-Reset header skeleton written out twice.
///
/// The `#if os(macOS)` column / `Form` split deliberately stays in each popover: the two macOS
/// bodies genuinely differ (Shadow hides two sections behind `shadow.isActive`), so a wrapper
/// taking two `@ViewBuilder`s would save nothing.

/// Uppercase label above a group of controls inside a popover.
struct PopoverSectionHeader: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: UIMetrics.FontSize.inlineLabel, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

/// Popover title row: name, an optional badge, and a trailing Reset button.
struct PopoverHeader: View {
    let title: LocalizedStringKey
    /// Rendered as an orange capsule after the title (e.g. "Beta"). `nil` shows nothing.
    var badge: LocalizedStringKey?
    var badgeHelp: LocalizedStringKey?
    let resetLabel: LocalizedStringKey
    let resetHelp: LocalizedStringKey
    let isResetDisabled: Bool
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))

            if let badge {
                Text(badge)
                    .font(.system(size: UIMetrics.FontSize.hint, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.orange.opacity(0.15), in: .capsule)
                    .help(badgeHelp ?? badge)
            }

            Spacer()

            Button(action: onReset) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(resetLabel)
                }
                .font(.system(size: UIMetrics.FontSize.body))
            }
            .buttonStyle(.borderless)
            .disabled(isResetDisabled)
            .help(resetHelp)
        }
    }
}

extension View {
    /// The dense desktop column a macOS bar popover presents its content in.
    func popoverColumn() -> some View {
        padding(14)
            .frame(width: 320)
            .font(.system(size: UIMetrics.FontSize.body))
    }
}
