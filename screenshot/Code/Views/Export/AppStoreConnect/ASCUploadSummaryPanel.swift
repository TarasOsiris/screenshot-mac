import SwiftUI

struct ASCUploadSummaryPanel: View {
    let entries: [UploadToAppStoreConnectView.UploadPlanEntry]
    let skipped: [UploadToAppStoreConnectView.UploadPlanEntry]
    let rowGroups: [UploadToAppStoreConnectView.UploadRowGroup]
    let versionCount: Int
    let localeCount: Int
    let screenshotCount: Int
    let issues: [ASCUploadIssue]
    @Binding var isExpanded: Bool
    let isBusy: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                metrics
                selectedUploads
                skippedItems
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ASCDisclosureChevronButton(expanded: isExpanded) {
                isExpanded.toggle()
            } label: {
                Text("Preflight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
            if issues.hasErrors {
                Label("Fix required", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
            Button("Refresh App Store data", action: onRefresh)
                .font(.caption)
                .disabled(isBusy)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            ASCSummaryMetric(value: "\(entries.count)", label: "sets")
            ASCSummaryMetric(value: "\(versionCount)", label: "versions")
            ASCSummaryMetric(value: "\(screenshotCount)", label: "screenshots")
            ASCSummaryMetric(value: "\(localeCount)", label: "locales")
        }
    }

    @ViewBuilder
    private var selectedUploads: some View {
        if !rowGroups.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Selected uploads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(rowGroups) { group in
                    ASCRowPlanGroupRow(group: group)
                }
            }
        }
    }

    @ViewBuilder
    private var skippedItems: some View {
        if !skipped.isEmpty {
            DisclosureGroup("Skipped items (\(skipped.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(skipped.prefix(12)) { entry in
                        ASCSkippedPlanEntryRow(entry: entry)
                    }
                    if skipped.count > 12 {
                        Text("\(skipped.count - 12) more skipped item\(skipped.count - 12 == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            .font(.caption)
        }
    }
}

private struct ASCSummaryMetric: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }
}

private struct ASCRowPlanGroupRow: View {
    let group: UploadToAppStoreConnectView.UploadRowGroup

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
                Text("\(group.screenshotCount) screenshot\(group.screenshotCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Source \(group.sourceSizeLabel) · \(group.templateCount) screenshot\(group.templateCount == 1 ? "" : "s") · \(group.displayTypeRawValue)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.caption2)
                Text(verbatim: compactLocaleSummary)
                    .font(.caption2)
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
        let noun = labels.count == 1 ? String(localized: "locale") : String(localized: "locales")
        let suffix = hiddenCount > 0 ? ", +\(hiddenCount)" : ""
        return "\(labels.count) \(noun): \(visible.joined(separator: ", "))\(suffix)"
    }

    private var fullLocaleSummary: String {
        localeLabels.joined(separator: ", ")
    }
}

private struct ASCSkippedPlanEntryRow: View {
    let entry: UploadToAppStoreConnectView.UploadPlanEntry

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
