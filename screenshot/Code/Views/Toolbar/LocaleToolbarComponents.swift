import SwiftUI

struct LocaleFlagChip: View {
    let locale: LocaleDefinition
    let isActive: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !locale.flag.isEmpty {
                    Text(locale.flag)
                        .font(.system(size: 13))
                }
                Text(locale.code.uppercased())
                    .font(.system(size: UIMetrics.FontSize.inlineLabel, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .frame(height: UIMetrics.IconButton.frameSize)
            .background(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                    .fill(isActive
                          ? Color.accentColor
                          : Color.primary.opacity(UIMetrics.Opacity.sectionFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip, style: .continuous)
                    .strokeBorder(
                        isActive
                          ? Color.accentColor
                          : Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay),
                        lineWidth: isActive
                          ? UIMetrics.BorderWidth.emphasis
                          : UIMetrics.BorderWidth.hairline
                    )
            )
            .shadow(
                color: isActive ? Color.accentColor.opacity(0.35) : .clear,
                radius: isActive ? 4 : 0,
                x: 0,
                y: isActive ? 1 : 0
            )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 4
    var verticalSpacing: CGFloat = 4

    // Avoid SwiftUI's tiny layout probes making the toolbar report dozens of wrapped rows.
    private static let minMeasuredWidth: CGFloat = 460

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(proposal.width ?? .infinity, Self.minMeasuredWidth)
        return arrange(subviews: subviews, maxWidth: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(subviews: subviews, maxWidth: bounds.width).positions
        for (index, point) in positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var y: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0 && rowWidth + horizontalSpacing + size.width > maxWidth {
                maxRowWidth = max(maxRowWidth, rowWidth)
                y += rowHeight + verticalSpacing
                rowWidth = 0
                rowHeight = 0
            }
            let x = rowWidth == 0 ? 0 : rowWidth + horizontalSpacing
            positions.append(CGPoint(x: x, y: y))
            rowWidth = x + size.width
            rowHeight = max(rowHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, rowWidth)
        return (positions, CGSize(width: maxRowWidth, height: y + rowHeight))
    }
}
