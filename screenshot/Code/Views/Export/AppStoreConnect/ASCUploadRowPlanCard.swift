import SwiftUI

/// Everything the locale rows need for the "Create in App Store Connect" action. One value
/// rather than a parameter each because it passes through two container views untouched.
struct ASCLocaleCreationContext {
    let versionId: String
    /// App Store Connect rejects a new localization on a version it won't take screenshots for,
    /// so a locked version keeps the plain hint instead of a button that can only 409.
    let versionAcceptsNewLocales: Bool
    /// Lowercased App Store locale codes the version already has.
    let existingStoreLocaleCodes: Set<String>
    let inFlightKeys: Set<String>
    let errors: [String: String]
    let create: (String) -> Void

    func key(projectLocaleCode: String) -> String {
        ASCUploadFlowModel.localeCreationKey(versionId: versionId, projectLocaleCode: projectLocaleCode)
    }

    /// The App Store locale a project locale would be created as, or nil when there is nothing
    /// worth offering: no App Store language for it, a locked version, or a code the version
    /// already carries (which happens when a longer project locale claimed it first).
    func creatableStoreCode(forProjectCode code: String) -> String? {
        guard versionAcceptsNewLocales,
              let storeCode = ASCLanguageMatcher.appStoreLanguageCode(forProjectCode: code),
              !existingStoreLocaleCodes.contains(storeCode.lowercased())
        else { return nil }
        return storeCode
    }
}

struct ASCUploadRowPlanCard: View {
    @Binding var plan: ASCRowPlan
    let detailsId: String
    let expanded: Bool
    let availableDisplayTypes: [ASCDisplayType]
    @Binding var displayTypeDetailsPlanId: String?
    let localeCreation: ASCLocaleCreationContext
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
                    ASCLocaleTargetRow(target: $target, creation: localeCreation)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(spacing: 6) {
            if plan.isEnabled {
                DisclosureChevronButton(expanded: expanded, action: onToggleExpanded)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.displayLabel)
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
                .accessibilityLabel("Include")
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct ASCDisplayTypePicker: View {
    @Binding var plan: ASCRowPlan
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
            Text(verbatim: plan.sizeLabel)
                .font(.caption)
            detectedDisplayTypeAction
            Spacer()
            detailsButton
        }
    }

    @ViewBuilder
    private var detectedDisplayTypeAction: some View {
        if let detected = plan.detectedAssetType, detected == plan.selectedAssetType, availableDisplayTypes.contains(detected) {
            Label("Auto-detected", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.caption)
        } else if let detected = plan.detectedAssetType, availableDisplayTypes.contains(detected) {
            Button {
                plan.selectedAssetType = detected
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
        .accessibilityLabel("Details")
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
                Button("Select…") { plan.selectedAssetType = nil }
                ForEach(displayTypeGroups, id: \.0) { title, items in
                    if !items.isEmpty {
                        Section(title) {
                            ForEach(items) { type in
                                Button(type.label) { plan.selectedAssetType = type }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(plan.selectedAssetType?.label ?? "Select…")
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
            if let selected = plan.selectedAssetType {
                Text(selected.appStoreConnectValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct ASCDisplayTypeDetailsPopover: View {
    let plan: ASCRowPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text(verbatim: plan.sizeLabel)
            }
            LabeledContent("Auto-detected") {
                Text(plan.detectedAssetType?.label ?? "No exact match")
            }
            if let selected = plan.selectedAssetType {
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
    @Binding var target: ASCLocaleTarget
    let creation: ASCLocaleCreationContext

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
                    .font(.caption)
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
                if let storeCode = creation.creatableStoreCode(forProjectCode: target.appLocaleCode) {
                    createLocaleAction(storeCode: storeCode)
                } else {
                    Text("Add this locale in App Store Connect, then refresh locales.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let failure = creation.errors[creation.key(projectLocaleCode: target.appLocaleCode)] {
                    Text("Could not create this locale: \(failure)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
    private func createLocaleAction(storeCode: String) -> some View {
        if creation.inFlightKeys.contains(creation.key(projectLocaleCode: target.appLocaleCode)) {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                Text("Creating…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            Button {
                creation.create(target.appLocaleCode)
            } label: {
                Label("Create \(storeCode) in App Store Connect", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
    }

    @ViewBuilder
    private var selectedLocaleLabel: some View {
        let selected = target.selectedCandidates.map(\.attributes.locale)
        if !selected.isEmpty {
            Text("-> \(selected.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
