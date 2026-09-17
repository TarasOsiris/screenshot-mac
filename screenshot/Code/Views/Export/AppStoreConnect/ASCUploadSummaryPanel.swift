import SwiftUI

struct ASCUploadSummaryPanel: View {
    /// The whole memo, not six fields off it: splatting them apart re-opened the drift the
    /// single build was meant to close.
    let plan: ASCUploadPlanEntries
    let issues: [UploadIssue]
    @Binding var isExpanded: Bool
    let isBusy: Bool
    let onRefresh: () -> Void

    var body: some View {
        StorePreflightPanel(
            isExpanded: $isExpanded,
            hasErrors: issues.hasErrors,
            refresh: StorePreflightRefresh(
                title: "Refresh App Store data",
                isBusy: isBusy,
                action: onRefresh
            )
        ) {
            StoreSummaryMetric(value: "\(plan.selected.count)", label: "sets")
            StoreSummaryMetric(value: "\(plan.versionCount)", label: "versions")
            StoreSummaryMetric(value: "\(plan.screenshotCount)", label: "screenshots")
            StoreSummaryMetric(value: "\(plan.localeCount)", label: "locales")
        } details: {
            selectedUploads
            skippedItems
        }
    }

    @ViewBuilder
    private var selectedUploads: some View {
        if !plan.rowGroups.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Selected uploads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(plan.rowGroups) { group in
                    ASCRowPlanGroupRow(group: group)
                }
            }
        }
    }

    @ViewBuilder
    private var skippedItems: some View {
        if !plan.skipped.isEmpty {
            DisclosureGroup("Skipped items (\(plan.skipped.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.skipped.prefix(12)) { entry in
                        ASCSkippedPlanEntryRow(entry: entry)
                    }
                    if plan.skipped.count > 12 {
                        Text(moreSkippedItemsText(plan.skipped.count - 12))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }

    private func moreSkippedItemsText(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 more skipped item")
            : String(localized: "\(count) more skipped items")
    }
}

private struct ASCRowPlanGroupRow: View {
    let group: ASCUploadRowGroup

    private static let visibleLocaleLimit = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                HStack(spacing: 5) {
                    ASCPlatformBadge(platform: group.destinationPlatform, style: .iconOnly)
                    Text("\(group.destinationLabel) · \(group.rowLabel) -> \(group.displayTypeLabel)")
                        .lineLimit(1)
                }
                .font(.caption)
                .fontWeight(.semibold)
                Spacer()
                Text(screenshotCountText(group.screenshotCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(sourceSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text(verbatim: compactLocaleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .help(fullLocaleSummary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullLocaleSummary)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 6))
    }

    private var localeLabels: [String] {
        group.entries.map { entry in
            let targetCode = entry.appStoreLocaleCode ?? entry.projectLocaleCode
            return entry.projectLocaleCode == targetCode
                ? targetCode
                : "\(entry.projectLocaleCode) -> \(targetCode)"
        }
    }

    private var compactLocaleSummary: String {
        let labels = localeLabels
        let visible = labels.prefix(Self.visibleLocaleLimit)
        let hiddenCount = labels.count - visible.count
        let suffix = hiddenCount > 0 ? ", +\(hiddenCount)" : ""
        let prefix = labels.count == 1
            ? String(localized: "1 locale")
            : String(localized: "\(labels.count) locales")
        return "\(prefix): \(visible.joined(separator: ", "))\(suffix)"
    }

    private var fullLocaleSummary: String {
        localeLabels.joined(separator: ", ")
    }

    private var sourceSummaryText: String {
        group.templateCount == 1
            ? String(localized: "Source \(group.sourceSizeLabel) · 1 screenshot · \(group.displayTypeRawValue)")
            : String(localized: "Source \(group.sourceSizeLabel) · \(group.templateCount) screenshots · \(group.displayTypeRawValue)")
    }

    private func screenshotCountText(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 screenshot")
            : String(localized: "\(count) screenshots")
    }
}

private struct ASCSkippedPlanEntryRow: View {
    let entry: ASCUploadPlanEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            ASCPlatformBadge(platform: entry.destinationPlatform, style: .iconOnly)
            Text("\(entry.destinationLabel) · \(entry.projectLocaleLabel) · \(entry.rowLabel): \(entry.skipReason ?? String(localized: "Skipped"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
