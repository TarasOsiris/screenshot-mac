import SwiftUI

struct ASCUploadSummaryPanel: View {
    let entries: [UploadToAppStoreConnectView.UploadPlanEntry]
    let skipped: [UploadToAppStoreConnectView.UploadPlanEntry]
    let groups: [UploadToAppStoreConnectView.UploadLocaleGroup]
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
            ASCSummaryMetric(value: "\(screenshotCount)", label: "screenshots")
            ASCSummaryMetric(value: "\(groups.count)", label: "locales")
        }
    }

    @ViewBuilder
    private var selectedUploads: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Selected uploads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(groups) { group in
                    ASCLocalePlanGroupRow(group: group)
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

private struct ASCLocalePlanGroupRow: View {
    let group: UploadToAppStoreConnectView.UploadLocaleGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(group.screenshotCount) screenshot\(group.screenshotCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.entries) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(entry.rowLabel) -> \(entry.displayTypeLabel)")
                            .font(.caption)
                            .lineLimit(1)
                        Text("Source \(entry.sourceSizeLabel) · \(entry.templateCount) screenshot\(entry.templateCount == 1 ? "" : "s") · \(entry.displayTypeRawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 6))
    }
}

private struct ASCSkippedPlanEntryRow: View {
    let entry: UploadToAppStoreConnectView.UploadPlanEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text("\(entry.projectLocaleLabel) · \(entry.rowLabel): \(entry.skipReason ?? String(localized: "Skipped"))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ASCReplaceWarningCallout: View {
    var body: some View {
        ASCCalloutBox(tint: .orange) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13))
                Text("If a matching display type already has screenshots, they will be deleted and replaced. You'll be asked to confirm before anything is uploaded.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct ASCIssuesPanel: View {
    let issues: [ASCUploadIssue]

    var body: some View {
        if !issues.isEmpty {
            ASCCalloutBox(tint: issues.hasErrors ? .red : .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        ASCIssueRow(issue: issue)
                    }
                }
            }
        }
    }
}

private struct ASCIssueRow: View {
    let issue: ASCUploadIssue

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity.tint)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                message
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = issue.hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var message: Text {
        if let scope = issue.scope {
            return Text(scope).fontWeight(.semibold) + Text(" · ") + Text(issue.message)
        }
        return Text(issue.message)
    }
}

struct ASCUploadRowPlanCard: View {
    @Binding var plan: UploadToAppStoreConnectView.RowPlan
    let expanded: Bool
    let availableDisplayTypes: [ASCDisplayType]
    @Binding var displayTypeDetailsPlanId: UUID?
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if expanded && plan.isEnabled {
                ASCDisplayTypePicker(
                    plan: $plan,
                    availableDisplayTypes: availableDisplayTypes,
                    displayTypeDetailsPlanId: $displayTypeDetailsPlanId
                )

                Text("Locales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach($plan.localeTargets) { $target in
                    ASCLocaleTargetRow(target: $target)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack {
            ASCDisclosureChevronButton(expanded: expanded, action: onToggleExpanded)
            Toggle(isOn: $plan.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel)
                        .fontWeight(.medium)
                    Text("\(String(Int(plan.rowSize.width)))×\(String(Int(plan.rowSize.height))) · \(plan.templateCount) screenshot\(plan.templateCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            Spacer()
        }
    }
}

private struct ASCDisplayTypePicker: View {
    @Binding var plan: UploadToAppStoreConnectView.RowPlan
    let availableDisplayTypes: [ASCDisplayType]
    @Binding var displayTypeDetailsPlanId: UUID?

    private var displayTypeGroups: [(String, [ASCDisplayType])] {
        [
            ("iPhone", availableDisplayTypes.filter { $0.family == .iphone }),
            ("iPad", availableDisplayTypes.filter { $0.family == .ipad }),
            ("Mac", availableDisplayTypes.filter { $0.family == .mac }),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            sourceRow
            targetRow
        }
    }

    private var sourceRow: some View {
        HStack {
            Text("Source")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(verbatim: "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))")
                .font(.caption)
            detectedDisplayTypeAction
            Spacer()
            detailsButton
        }
    }

    @ViewBuilder
    private var detectedDisplayTypeAction: some View {
        if let detected = plan.detectedDisplayType, detected == plan.selectedDisplayType {
            Label("Auto-detected", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.caption)
        } else if let detected = plan.detectedDisplayType {
            Button {
                plan.selectedDisplayType = detected
            } label: {
                Label("Use detected (\(detected.label))", systemImage: "wand.and.stars")
            }
            .font(.caption)
            .buttonStyle(.borderless)
        }
    }

    private var detailsButton: some View {
        Button {
            displayTypeDetailsPlanId = plan.id
        } label: {
            Image(systemName: "info.circle")
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { displayTypeDetailsPlanId == plan.id },
            set: { isPresented in
                if !isPresented { displayTypeDetailsPlanId = nil }
            }
        )) {
            ASCDisplayTypeDetailsPopover(plan: plan)
        }
    }

    private var targetRow: some View {
        HStack {
            Text("Upload as")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Menu {
                Button("Select…") { plan.selectedDisplayType = nil }
                ForEach(displayTypeGroups, id: \.0) { title, items in
                    if !items.isEmpty {
                        Section(title) {
                            ForEach(items) { type in
                                Button(type.label) { plan.selectedDisplayType = type }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(plan.selectedDisplayType?.label ?? "Select…")
                        .lineLimit(1)
                    Spacer()
                    #if os(iOS)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    #endif
                }
            }
            #if os(macOS)
            .menuStyle(.borderlessButton)
            .frame(maxWidth: 340, alignment: .leading)
            #else
            .buttonStyle(.bordered)
            #endif
            if let selected = plan.selectedDisplayType {
                Text(selected.appStoreConnectValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ASCDisplayTypeDetailsPopover: View {
    let plan: UploadToAppStoreConnectView.RowPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text(verbatim: "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))")
            }
            LabeledContent("Auto-detected") {
                Text(plan.detectedDisplayType?.label ?? "No exact match")
            }
            if let selected = plan.selectedDisplayType {
                LabeledContent("Upload target") {
                    Text(selected.label)
                }
                LabeledContent("ASC value") {
                    Text(selected.appStoreConnectValue)
                        .font(.caption.monospaced())
                }
                LabeledContent("Accepted sizes") {
                    Text(selected.acceptedSizeDescription)
                        .multilineTextAlignment(.trailing)
                }
                if selected.family == .ipad {
                    Label("App Store Connect rejects this if the selected app version is iPhone-only.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 360)
        #else
        .frame(maxWidth: 360)
        #endif
    }
}

private struct ASCLocaleTargetRow: View {
    @Binding var target: UploadToAppStoreConnectView.LocaleTarget

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            localeToggle
            localeSelection
        }
    }

    private var localeToggle: some View {
        Toggle(isOn: $target.isEnabled) {
            VStack(alignment: .leading, spacing: 1) {
                Text(target.appLocaleLabel)
                Text("Project \(target.appLocaleCode)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            #if os(macOS)
            .frame(width: 150, alignment: .leading)
            #else
            .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        #if os(macOS)
        .toggleStyle(.checkbox)
        #else
        .toggleStyle(.switch)
        .controlSize(.small)
        #endif
        .disabled(target.candidates.isEmpty)
    }

    @ViewBuilder
    private var localeSelection: some View {
        if target.candidates.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("No matching App Store locale")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("Add this locale in App Store Connect, then refresh locales.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("", selection: $target.selectedASCLocalizationId) {
                Text("Choose…").tag(String?.none)
                ForEach(target.candidates) { candidate in
                    Text(candidate.attributes.locale).tag(Optional(candidate.id))
                }
            }
            .labelsHidden()
            #if os(iOS)
            .pickerStyle(.menu)
            #endif
            .disabled(!target.isEnabled)
            selectedLocaleLabel
        }
    }

    @ViewBuilder
    private var selectedLocaleLabel: some View {
        if let selectedId = target.selectedASCLocalizationId,
           let selected = target.candidates.first(where: { $0.id == selectedId }) {
            Text("-> \(selected.attributes.locale)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct ASCCalloutBox<Content: View>: View {
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }
}

struct ASCDisclosureChevronButton<Label: View>: View {
    let expanded: Bool
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    init(
        expanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label = { EmptyView() }
    ) {
        self.expanded = expanded
        self.action = action
        self.label = label
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                label()
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
