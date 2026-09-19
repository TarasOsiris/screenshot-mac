import SwiftUI

/// What one locale row can say about the screenshots App Store Connect already holds for it.
enum ASCLocalePresenceState {
    /// At least one matched candidate hasn't been checked yet.
    case checking
    case hasScreenshots
    case missing
}

/// Everything the locale rows need that a row can't derive from its own target: the "Create in
/// App Store Connect" action, and what App Store Connect already holds. One value rather than a
/// parameter each because it passes through two container views untouched.
struct ASCLocaleRowContext {
    let versionId: String
    /// App Store Connect rejects a new localization on a version it won't take screenshots for,
    /// so a locked version keeps the plain hint instead of a button that can only 409.
    let versionAcceptsNewLocales: Bool
    /// Lowercased App Store locale codes the version already has.
    let existingStoreLocaleCodes: Set<String>
    let inFlightKeys: Set<String>
    let errors: [String: String]
    /// Per version-localization, the display types holding screenshots. An absent key means
    /// "not checked yet", which is why this can't collapse to a set of ids.
    let screenshotDisplayTypesByLocalizationId: [String: Set<String>]
    let create: (String) -> Void

    func key(projectLocaleCode: String) -> String {
        ASCUploadFlowModel.localeCreationKey(versionId: versionId, projectLocaleCode: projectLocaleCode)
    }

    /// Scoped to the display type the row will actually upload: App Store Connect carries
    /// screenshots over between versions and keeps sets for device families a row isn't targeting,
    /// and counting those made a locale with nothing for the selected size look fine. Falls back
    /// to "any display type" only while the row has no upload target chosen.
    func presenceState(
        candidates: [ASCAppStoreVersionLocalization],
        displayType: ASCDisplayType?
    ) -> ASCLocalePresenceState {
        // An unmatched locale has nothing on App Store Connect to be missing screenshots *from*,
        // and `allSatisfy` below is vacuously true — which would accuse it. The row renders a
        // different branch entirely for this case; the guard is here so the answer can't be wrong
        // if anything else ever asks.
        guard !candidates.isEmpty else { return .hasScreenshots }
        var populatedPerCandidate: [Set<String>] = []
        for candidate in candidates {
            guard let populated = screenshotDisplayTypesByLocalizationId[candidate.id] else { return .checking }
            populatedPerCandidate.append(populated)
        }
        let isEmptyForRow: (Set<String>) -> Bool = { populated in
            guard let displayType else { return populated.isEmpty }
            return !populated.contains(displayType.appStoreConnectValue)
        }
        return populatedPerCandidate.allSatisfy(isEmptyForRow) ? .missing : .hasScreenshots
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
    let localeCreation: ASCLocaleRowContext
    let onToggleExpanded: () -> Void

    var body: some View {
        StoreUploadRowPlanCard(
            title: plan.displayLabel,
            sizeSummary: plan.sizeAndCountSummary,
            foreignPlatformHint: plan.inferredStorePlatform == .android ? "Looks like an Android row" : nil,
            isEnabled: $plan.isEnabled,
            expanded: expanded,
            onToggleExpanded: onToggleExpanded
        ) {
            ASCDisplayTypePicker(
                plan: $plan,
                detailsId: detailsId,
                availableDisplayTypes: availableDisplayTypes,
                displayTypeDetailsPlanId: $displayTypeDetailsPlanId
            )

            HStack {
                Text("Locales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Select All", isOn: Binding(
                    get: { plan.allToggleableLocalesEnabled },
                    set: { plan.setAllLocaleTargets(enabled: $0) }
                ))
                .storeSelectionToggleStyle()
                .font(.caption)
                .disabled(!plan.hasToggleableLocaleTargets)
            }
            // A Grid rather than per-row HStacks: it measures every row and sizes the locale
            // column to the widest label, so the names align without a fixed width to truncate
            // "English (Australia) (EN-AU)" against.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                ForEach($plan.localeTargets) { $target in
                    ASCLocaleTargetRow(
                        target: $target,
                        creation: localeCreation,
                        displayType: plan.selectedAssetType
                    )
                }
            }
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
    let creation: ASCLocaleRowContext
    /// What this row plan uploads, which is what "has screenshots" has to be measured against.
    let displayType: ASCDisplayType?

    /// Exactly two cells: anything else here becomes its own Grid column and breaks the alignment
    /// the Grid exists to provide.
    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            localeToggle
            localeSelection
        }
    }

    private var localeToggle: some View {
        Toggle(isOn: $target.isEnabled) {
            Text(verbatim: "\(target.appLocaleLabel) (\(target.appLocaleCode.uppercased()))")
            #if os(iOS)
                .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
        .storeSelectionToggleStyle()
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(target.candidates) { candidate in
                        Toggle(candidate.attributes.locale, isOn: $target.selectedASCLocalizationIds.contains(candidate.id))
                            .storeSelectionToggleStyle()
                            .font(.caption)
                            .disabled(!target.isEnabled)
                    }
                }
                selectedLocaleLabel
                presenceLabel
            }
        }
    }

    @ViewBuilder
    private var presenceLabel: some View {
        switch creation.presenceState(candidates: target.candidates, displayType: displayType) {
        case .missing:
            Text("No screenshots yet")
                .font(.caption)
                .foregroundStyle(.orange)
        case .checking:
            // Named rather than silent: "no badge" would otherwise mean both "App Store Connect
            // has screenshots" and "we haven't looked yet", and the sweep takes a while.
            Text("Checking…")
                .font(.caption)
                .foregroundStyle(.tertiary)
        case .hasScreenshots:
            EmptyView()
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

    /// Only worth showing when it says something the checkboxes above don't: with everything
    /// ticked it just echoes them ("cs -> cs"), and with nothing ticked there is no destination
    /// to name.
    @ViewBuilder
    private var selectedLocaleLabel: some View {
        let selected = target.selectedCandidates.map(\.attributes.locale)
        if !selected.isEmpty, selected.count < target.candidates.count {
            Text(verbatim: "-> \(selected.joined(separator: ", "))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
