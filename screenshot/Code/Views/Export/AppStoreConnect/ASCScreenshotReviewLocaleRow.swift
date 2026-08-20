import SwiftUI

/// One locale of one device group: a scannable line, with the thumbnail strips only built when the
/// row is open — a plan holds up to 250 of these and each strip decodes up to 20 previews.
struct ASCScreenshotReviewLocaleRow: View {
    let set: ASCScreenshotSetDiff
    let isIncluded: Bool
    let isExpanded: Bool
    let onIncludedChange: (Bool) -> Void
    let onToggleExpanded: () -> Void

    /// `localeLabel` is the App Store locale identifier (`en-US`); `localeCode` is the project's.
    private var localeFlag: String { LocaleDefinition.flag(forCode: set.localeLabel) }
    private var localeName: String { LocaleDefinition.displayName(forCode: set.localeLabel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            summaryRow
            if isExpanded {
                detail
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.primary.opacity(isExpanded ? 0.05 : 0.025))
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            includeToggle
            disclosure
            Spacer(minLength: 8)
            statusSummary
        }
    }

    private var includeToggle: some View {
        Toggle("Include set", isOn: Binding(get: { isIncluded }, set: onIncludedChange))
            .labelsHidden()
            #if os(macOS)
            .toggleStyle(.checkbox)
            #else
            .toggleStyle(.switch)
            .controlSize(.small)
            #endif
            .disabled(!set.isChanged || !set.canApply)
            .accessibilityLabel("Include \(localeName)")
    }

    private var disclosure: some View {
        Button(action: onToggleExpanded) {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                if !localeFlag.isEmpty {
                    Text(localeFlag)
                        .font(.system(size: 14))
                }
                Text(localeName)
                    .lineLimit(1)
                Text(set.localeLabel)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(iOS)
            .frame(minHeight: 44)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(localeName) \(set.localeLabel)"))
        .accessibilityHint(isExpanded ? "Hide screenshots" : "Show screenshots")
    }

    @ViewBuilder
    private var statusSummary: some View {
        if !set.canApply {
            Label("Blocked", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if set.isChanged {
            HStack(spacing: 6) {
                ForEach(changeCounts, id: \.0) { status, count in
                    ASCScreenshotStatusCapsule(status: status, count: count)
                }
            }
        } else {
            Label("Already matches", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        }
    }

    /// Only the non-zero counts — four capsules on every row is noise when three of them read zero.
    private var changeCounts: [(ASCScreenshotDiffStatus, Int)] {
        [(.new, set.uploadCount), (.moved, set.moveCount), (.removed, set.removalCount)]
            .filter { $0.1 > 0 }
    }

    @ViewBuilder
    private var detail: some View {
        ASCScreenshotDiffStrip(title: "Current App Store", items: set.currentAssets, proposed: false)
        ASCScreenshotDiffStrip(title: "Proposed Screenshot Bro", items: set.proposedAssets, proposed: true)

        if set.currentAssets.contains(where: { $0.remoteAsset?.previewError != nil }) {
            Label("Some current screenshots could not be previewed. They are shown as placeholders; refresh to retry.", systemImage: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        if !set.issues.isEmpty || !set.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(set.issues + set.warnings, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if !set.canApply {
                    Text("This set cannot be included because required App Store data is unavailable.")
                        .font(.caption.bold())
                }
            }
        }
    }
}

private struct ASCScreenshotDiffStrip: View {
    let title: LocalizedStringKey
    let items: [ASCScreenshotDiffItem]
    let proposed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.bold())
            if items.isEmpty {
                Text("Empty set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(items) { item in
                            ASCScreenshotDiffThumbnail(
                                item: item,
                                proposed: proposed,
                                onPreview: previewURL(for: item).map { _ in { preview(item) } }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func previewURL(for item: ASCScreenshotDiffItem) -> URL? {
        proposed ? item.localAsset?.fileURL : item.remoteAsset?.previewFileURL
    }

    private func preview(_ selectedItem: ASCScreenshotDiffItem) {
        let previewableItems = items.compactMap { item -> (id: String, url: URL)? in
            guard let url = previewURL(for: item) else { return nil }
            return (item.id, url)
        }
        guard let selectedIndex = previewableItems.firstIndex(where: { $0.id == selectedItem.id }) else {
            return
        }
        QuickLookCoordinator.shared.preview(
            imagesAt: previewableItems.map { $0.url },
            startingAt: selectedIndex
        )
    }
}
