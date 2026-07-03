import SwiftUI

struct ASCUploadRowPlanCard: View {
    @Binding var plan: UploadToAppStoreConnectView.RowPlan
    let detailsId: String
    let expanded: Bool
    let availableDisplayTypes: [ASCDisplayType]
    @Binding var displayTypeDetailsPlanId: String?
    let onToggleExpanded: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if expanded && plan.isEnabled {
                ASCDisplayTypePicker(
                    plan: $plan,
                    detailsId: detailsId,
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
        HStack(spacing: 6) {
            if plan.isEnabled {
                ASCDisclosureChevronButton(expanded: expanded, action: onToggleExpanded)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel)
                    .fontWeight(.medium)
                Text("\(String(Int(plan.rowSize.width)))×\(String(Int(plan.rowSize.height))) · \(plan.templateCount) screenshot\(plan.templateCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if plan.inferredStorePlatform == .android {
                    Text("Looks like an Android row")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Toggle("", isOn: $plan.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct ASCDisplayTypePicker: View {
    @Binding var plan: UploadToAppStoreConnectView.RowPlan
    let detailsId: String
    let availableDisplayTypes: [ASCDisplayType]
    @Binding var displayTypeDetailsPlanId: String?

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
        if let detected = plan.detectedDisplayType, detected == plan.selectedDisplayType, availableDisplayTypes.contains(detected) {
            Label("Auto-detected", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.caption)
        } else if let detected = plan.detectedDisplayType, availableDisplayTypes.contains(detected) {
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
            displayTypeDetailsPlanId = detailsId
        } label: {
            Image(systemName: "info.circle")
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { displayTypeDetailsPlanId == detailsId },
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
            VStack(alignment: .leading, spacing: 2) {
                ForEach(target.candidates) { candidate in
                    Toggle(candidate.attributes.locale, isOn: $target.selectedASCLocalizationIds.contains(candidate.id))
                        #if os(macOS)
                        .toggleStyle(.checkbox)
                        #else
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        #endif
                        .font(.caption)
                        .disabled(!target.isEnabled)
                }
            }
            selectedLocaleLabel
        }
    }

    @ViewBuilder
    private var selectedLocaleLabel: some View {
        let selected = target.selectedCandidates.map(\.attributes.locale)
        if !selected.isEmpty {
            Text("-> \(selected.joined(separator: ", "))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
