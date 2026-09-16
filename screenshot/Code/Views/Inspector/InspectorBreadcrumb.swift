#if os(macOS)
import SwiftUI

/// "Row › Shape" header of the selection inspector. The row name is the way back to row settings,
/// as Esc is; the trailing slot holds the selection's actions.
struct InspectorBreadcrumb<Trailing: View>: View {
    let row: ScreenshotRow
    let icon: String
    let title: String
    let onSelectRow: () -> Void
    /// Sits with the resolution label because it is metadata about what is selected, not an action.
    var overrideChip: LocaleOverrideChip?
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Button(action: onSelectRow) {
                    Text(row.displayLabel)
                        .lineLimit(1)
                        .opacity(row.label.isEmpty ? 0.5 : 1)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Show row settings (Esc)")
                .layoutPriority(-1)

                Image(systemName: "chevron.forward")
                    .scaledFont(UIMetrics.FontSize.hint, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                Label(title, systemImage: icon)
                    .lineLimit(1)
                    .fixedSize()
            }
            .font(.headline)

            HStack(spacing: 8) {
                // Short and fixed, but it is the only flexible text on this line — without this a
                // narrow inspector squeezes it to zero width and wraps it one digit per line.
                Text(verbatim: row.resolutionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                overrideChip
                Spacer(minLength: 0)
                trailing()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}

/// Align and distribute buttons for a multi-shape selection — the context menu's Align Selected
/// submenu, laid out flat.
struct InspectorAlignmentBar: View {
    let canDistribute: Bool
    let onAlign: (ShapeAlignment) -> Void

    var body: some View {
        HStack(spacing: 2) {
            button("align.horizontal.left", "Align Left", .left)
            button("align.horizontal.center", "Align Center", .centerH)
            button("align.horizontal.right", "Align Right", .right)
            separator
            button("align.vertical.top", "Align Top", .top)
            button("align.vertical.center", "Align Middle", .centerV)
            button("align.vertical.bottom", "Align Bottom", .bottom)
            separator
            button("distribute.horizontal.center", "Distribute Horizontally", .distributeH, disabled: !canDistribute)
            button("distribute.vertical.center", "Distribute Vertically", .distributeV, disabled: !canDistribute)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var separator: some View {
        Divider()
            .frame(height: 14)
            .padding(.horizontal, 4)
    }

    private func button(_ icon: String, _ tooltip: LocalizedStringKey, _ alignment: ShapeAlignment, disabled: Bool = false) -> some View {
        ActionButton(icon: icon, tooltip: tooltip, frameSize: UIMetrics.IconButton.frameSize, disabled: disabled) {
            onAlign(alignment)
        }
    }
}
#endif
