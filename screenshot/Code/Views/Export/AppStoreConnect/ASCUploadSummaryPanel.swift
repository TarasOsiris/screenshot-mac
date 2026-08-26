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
            DisclosureChevronButton(expanded: isExpanded) {
                isExpanded.toggle()
            } label: {
                Text("Preflight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
            PreflightStatusLabel(hasErrors: issues.hasErrors, font: .caption)
            Button("Refresh App Store data", action: onRefresh)
                .font(.caption)
                .disabled(isBusy)
        }
    }

    private var metrics: some View {
        HStack(spacing: 10) {
            ASCSummaryMetric(value: "\(plan.selected.count)", label: "sets")
            ASCSummaryMetric(value: "\(plan.versionCount)", label: "versions")
            ASCSummaryMetric(value: "\(plan.screenshotCount)", label: "screenshots")
            ASCSummaryMetric(value: "\(plan.localeCount)", label: "locales")
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
                        Text("\(plan.skipped.count - 12) more skipped item\(plan.skipped.count - 12 == 1 ? "" : "s")")
                            .font(.caption)
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
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
                Text("\(group.screenshotCount) screenshot\(group.screenshotCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Source \(group.sourceSizeLabel) · \(group.templateCount) screenshot\(group.templateCount == 1 ? "" : "s") · \(group.displayTypeRawValue)")
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
        let noun = labels.count == 1 ? String(localized: "locale") : String(localized: "locales")
        let suffix = hiddenCount > 0 ? ", +\(hiddenCount)" : ""
        return "\(labels.count) \(noun): \(visible.joined(separator: ", "))\(suffix)"
    }

    private var fullLocaleSummary: String {
        localeLabels.joined(separator: ", ")
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
