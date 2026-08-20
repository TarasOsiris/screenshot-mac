import SwiftUI

/// One source row's sets, with the row/display-type stated once in the header instead of repeated
/// under every locale.
struct ASCScreenshotReviewDeviceGroupView: View {
    let group: ASCScreenshotReviewDeviceGroup
    let visibleSets: [ASCScreenshotSetDiff]
    let includedSetIds: Set<String>
    let expandedSetIds: Set<String>
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onToggleSetExpanded: (ASCScreenshotSetDiff) -> Void
    let onIncludedChange: (ASCScreenshotSetDiff, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded {
                if visibleSets.isEmpty {
                    Text("All \(group.sets.count) locales already match the App Store.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                } else {
                    ForEach(visibleSets) { set in
                        ASCScreenshotReviewLocaleRow(
                            set: set,
                            isIncluded: includedSetIds.contains(set.id),
                            isExpanded: expandedSetIds.contains(set.id),
                            onIncludedChange: { onIncludedChange(set, $0) },
                            onToggleExpanded: { onToggleSetExpanded(set) }
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            DisclosureChevronButton(expanded: isExpanded, action: onToggleExpanded) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(group.rowLabel) -> \(group.displayTypeLabel)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            aggregateCounts
        }
    }

    private var subtitle: String {
        if group.blockedCount > 0 {
            return String(localized: "\(group.sets.count) locales · \(group.changedCount) changed · \(includedCount) included · \(group.blockedCount) blocked")
        }
        return String(localized: "\(group.sets.count) locales · \(group.changedCount) changed · \(includedCount) included")
    }

    private var includedCount: Int {
        group.sets.count { includedSetIds.contains($0.id) }
    }

    @ViewBuilder
    private var aggregateCounts: some View {
        if group.changedCount == 0 {
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            HStack(spacing: 6) {
                ForEach(changeCounts, id: \.0) { status, count in
                    ASCScreenshotStatusCapsule(status: status, count: count)
                }
            }
        }
    }

    private var changeCounts: [(ASCScreenshotDiffStatus, Int)] {
        [(.new, group.uploadCount), (.moved, group.moveCount), (.removed, group.removalCount)]
            .filter { $0.1 > 0 }
    }
}
