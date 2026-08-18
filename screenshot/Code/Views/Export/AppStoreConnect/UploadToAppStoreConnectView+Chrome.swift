import SwiftUI

extension UploadToAppStoreConnectView {
    var confirmationMessage: String {
        if isConfirmingReviewedSync {
            screenshotSync.confirmationSummary
        } else {
            directUploadConfirmationMessage
        }
    }

    var directUploadConfirmationMessage: String {
        let entries = selectedUploadPlanEntries
        let screenshotCount = entries.reduce(0) { $0 + $1.screenshotCount }
        let localeCount = Set(entries.map { "\($0.destinationId)|\($0.appStoreLocaleCode ?? $0.projectLocaleCode)" }).count
        let versionCount = Set(entries.map(\.destinationId)).count
        let setCount = entries.count
        let screenshotNoun = screenshotCount == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let setNoun = setCount == 1 ? String(localized: "set") : String(localized: "sets")
        let localeNoun = localeCount == 1 ? String(localized: "locale") : String(localized: "locales")
        let versionNoun = versionCount == 1 ? String(localized: "version") : String(localized: "versions")
        return String(localized: "\(screenshotCount) \(screenshotNoun) will be safely synced across \(setCount) \(setNoun), \(localeCount) \(localeNoun), and \(versionCount) \(versionNoun). Exact checksum matches will be preserved.")
    }

    // MARK: - Header / footer

    var flowTitle: LocalizedStringKey {
        mode == .metadata ? "Update App Store Metadata" : "Sync App Store Screenshots"
    }

    var header: some View {
        HStack {
            Image(systemName: mode == .metadata ? "text.badge.checkmark" : "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            Text(flowTitle)
                .font(.headline)
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var demoModeBanner: some View {
        DemoModeBanner(message: "Sample apps and a simulated screenshot sync. Nothing is sent to App Store Connect.")
    }

    var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            backButton
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Details") { presentErrorDetails(fallback: errorMessage) }
                    .font(.caption)
                    .buttonStyle(.borderless)
            }
            Spacer()
            dismissButton
            reviewChangesButton
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Show the full failure text, preferring the detailed report and falling back to the
    /// short banner message. Shared by the macOS footer and the iPad error banner.
    func presentErrorDetails(fallback message: String) {
        presentedErrorDetails = UploadFailureDetail(message: errorDetailsText ?? message)
    }

    @ViewBuilder
    var backButton: some View {
        switch step {
        case .pickingVersion, .editingMetadata, .configuringPlan, .reviewingChanges:
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(isBusy)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    var dismissButton: some View {
        switch step {
        case .uploading:
            Button("Cancel Sync", role: .cancel) { cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(screenshotSync.phase == .applying)
        }
    }

    /// The forward primary action for the pre-upload steps (Next / Continue / Upload / Sync),
    /// shared by the macOS footer button and the iPad nav-bar button so titles, actions, and
    /// enabled rules stay in lockstep. `nil` on the terminal uploading/done screens.
    struct ForwardPrimary {
        let titleKey: LocalizedStringKey
        let action: () -> Void
        let isEnabled: Bool
    }

    func forwardPrimary(for step: Step) -> ForwardPrimary? {
        switch step {
        case .pickingApp:
            ForwardPrimary(titleKey: "Next", action: { Task { await moveToVersion() } },
                           isEnabled: selectedApp != nil && !isBusy)
        case .pickingVersion:
            ForwardPrimary(titleKey: "Next", action: { Task { await movePastVersionSelection() } },
                           isEnabled: canAdvanceFromVersion && !isBusy)
        case .editingMetadata:
            ForwardPrimary(titleKey: metadataPrimaryTitle,
                           action: { Task { await saveMetadataAndContinue() } },
                           isEnabled: !isBusy)
        case .configuringPlan:
            ForwardPrimary(titleKey: "Upload", action: { requestDirectUpload() },
                           isEnabled: canStartUpload && !isBusy)
        case .reviewingChanges:
            ForwardPrimary(titleKey: "Sync Selected Sets", action: { requestReviewedSync() },
                           isEnabled: screenshotSync.canApply && !isBusy)
        case .uploading, .done:
            nil
        }
    }

    @ViewBuilder
    var primaryButton: some View {
        if let primary = forwardPrimary(for: step) {
            Button(primary.titleKey, action: primary.action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!primary.isEnabled)
        }
    }

    @ViewBuilder
    var reviewChangesButton: some View {
        if step == .configuringPlan {
            Button("Review Changes", action: startScreenshotReviewBuild)
                .disabled(!canStartUpload || isBusy)
        }
    }

    func requestDirectUpload() {
        isConfirmingReviewedSync = false
        isConfirmingUpload = true
    }

    func requestReviewedSync() {
        isConfirmingReviewedSync = true
        isConfirmingUpload = true
    }

    var metadataPrimaryTitle: LocalizedStringKey {
        switch (mode, hasMetadataChanges) {
        case (.metadata, true): "Save"
        case (.metadata, false): "Done"
        case (.screenshots, true): "Save & Continue"
        case (.screenshots, false): "Continue"
        }
    }

    var hasMetadataChanges: Bool {
        if copyrightByVersion.contains(where: { $0.value != (originalCopyrightByVersion[$0.key] ?? "") }) { return true }
        if versionDrafts.contains(where: \.isChanged) { return true }
        if appInfoDrafts.contains(where: \.isChanged) { return true }
        return false
    }

    var canAdvanceFromVersion: Bool {
        !selectedVersions.isEmpty && selectedVersions.allSatisfy { $0.isSelectable(for: mode) }
    }

    func goBack() {
        errorMessage = nil
        errorDetailsText = nil
        switch step {
        case .pickingVersion:
            step = .pickingApp
        case .editingMetadata:
            step = .pickingVersion
        case .configuringPlan:
            step = .editingMetadata
        case .reviewingChanges:
            screenshotSync.discard()
            step = .configuringPlan
        default: break
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
    }

    var validationIssues: [UploadIssue] {
        AppStoreConnectUploadValidator.validate(
            destinations: destinationPlans,
            isDemoMode: credentials.isDemoMode
        )
    }

    var canStartUpload: Bool {
        !validationIssues.hasErrors
    }

    var uploadPlanEntries: [UploadPlanEntry] {
        destinationPlans.flatMap { destination -> [UploadPlanEntry] in
            destination.rowPlans.flatMap { plan -> [UploadPlanEntry] in
                guard plan.isEnabled else { return [] }
                let rowLabel = plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel
                let sourceSizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"
                let displayTypeLabel = plan.selectedAssetType?.label ?? String(localized: "No display type selected")
                let displayTypeRawValue = plan.selectedAssetType?.appStoreConnectValue ?? "none"

                return plan.localeTargets.flatMap { target -> [UploadPlanEntry] in
                    func entry(idSuffix: String, appStoreLocaleCode: String?, isSelected: Bool, skipReason: String?) -> UploadPlanEntry {
                        UploadPlanEntry(
                            id: "\(destination.id)-\(plan.id.uuidString)-\(target.id.uuidString)\(idSuffix)",
                            destinationId: destination.id,
                            destinationLabel: destination.title,
                            destinationPlatform: destination.version.attributes.ascPlatform,
                            rowPlanId: plan.id,
                            rowLabel: rowLabel,
                            sourceSizeLabel: sourceSizeLabel,
                            displayTypeLabel: displayTypeLabel,
                            displayTypeRawValue: displayTypeRawValue,
                            projectLocaleLabel: target.appLocaleLabel,
                            projectLocaleCode: target.appLocaleCode,
                            appStoreLocaleCode: appStoreLocaleCode,
                            templateCount: plan.templateCount,
                            isSelected: isSelected,
                            skipReason: skipReason
                        )
                    }

                    let selectedCandidates = target.selectedCandidates
                    if target.isEnabled, plan.selectedAssetType != nil, !selectedCandidates.isEmpty {
                        // One entry per App Store destination this locale fans out to.
                        return selectedCandidates.map { candidate in
                            entry(idSuffix: "-\(candidate.id)", appStoreLocaleCode: candidate.attributes.locale, isSelected: true, skipReason: nil)
                        }
                    }

                    let skipReason: String
                    if target.candidates.isEmpty {
                        skipReason = String(localized: "No matching App Store locale")
                    } else if !target.isEnabled {
                        skipReason = String(localized: "Unchecked")
                    } else if plan.selectedAssetType == nil {
                        skipReason = String(localized: "No display type selected")
                    } else {
                        skipReason = String(localized: "No App Store locale selected")
                    }
                    return [entry(idSuffix: "", appStoreLocaleCode: nil, isSelected: false, skipReason: skipReason)]
                }
            }
        }
    }

    var selectedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter(\.isSelected)
    }

    var skippedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter { !$0.isSelected }
    }

    var selectedLocaleGroups: [UploadLocaleGroup] {
        localeGroups(from: selectedUploadPlanEntries)
    }

    /// Group already-filtered entries by App Store (or project) locale. Takes the entries as a
    /// parameter so callers that already computed `uploadPlanEntries` don't recompute it.
    func localeGroups(from entries: [UploadPlanEntry]) -> [UploadLocaleGroup] {
        let grouped = Dictionary(grouping: entries) { entry in
            "\(entry.destinationId)|\(entry.appStoreLocaleCode ?? entry.projectLocaleCode)"
        }
        return grouped.keys.sorted().map { code in
            let groupEntries = grouped[code] ?? []
            let label = groupEntries.first.map { "\($0.destinationLabel) · \($0.projectLocaleLabel) -> \($0.appStoreLocaleCode ?? $0.projectLocaleCode)" } ?? code
            return UploadLocaleGroup(id: code, label: label, entries: groupEntries)
        }
    }

    /// Group entries by source row, preserving the row order in which they were generated, so the
    /// constant row/display-type details render once instead of repeating under every locale.
    func rowGroups(from entries: [UploadPlanEntry]) -> [UploadRowGroup] {
        var order: [String] = []
        var grouped: [String: [UploadPlanEntry]] = [:]
        for entry in entries {
            let key = "\(entry.destinationId)|\(entry.rowPlanId.uuidString)"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(entry)
        }
        return order.compactMap { key in
            guard let groupEntries = grouped[key], let first = groupEntries.first else { return nil }
            return UploadRowGroup(
                id: key,
                destinationLabel: first.destinationLabel,
                destinationPlatform: first.destinationPlatform,
                rowLabel: first.rowLabel,
                sourceSizeLabel: first.sourceSizeLabel,
                displayTypeLabel: first.displayTypeLabel,
                displayTypeRawValue: first.displayTypeRawValue,
                templateCount: first.templateCount,
                entries: groupEntries
            )
        }
    }
}
