import SwiftUI

/// The review header, kept out of the scroll view — with 90+ sets the old inline header (and its
/// Refresh button) scrolled away after the first card.
struct ASCScreenshotReviewToolbar: View {
    let outline: ASCScreenshotReviewOutline
    let totals: ASCScreenshotSelectionTotals
    let expiresAt: Date
    let isBusy: Bool
    @Binding var showsUnchanged: Bool
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow
            summaryRow
            controlsRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Review Changes")
                    .font(.title2.bold())
                Text("Only included, changed sets will be synced. Exact checksum matches are preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isBusy)
                Text("Expires \(expiresAt, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 6) {
            Text("\(totals.setCount) of \(outline.changedCount) changed sets included")
                .font(.subheadline.weight(.medium))
            if totals.setCount > 0 {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("\(totals.uploads) uploads, \(totals.removals) removals, \(totals.moves) moves")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if outline.blockedCount > 0 {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("\(outline.blockedCount) blocked")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
        }
        .lineLimit(1)
    }

    private var controlsRow: some View {
        HStack(spacing: 10) {
            Button("Select All Changed", action: onSelectAll)
                .disabled(isBusy || totals.setCount == outline.changedCount)
            Button("Deselect All", action: onDeselectAll)
                .disabled(isBusy || totals.setCount == 0)
            Spacer()
            if outline.unchangedCount > 0 {
                Toggle("Show unchanged (\(outline.unchangedCount))", isOn: $showsUnchanged)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
            }
        }
    }
}
