import SwiftUI

extension UploadToAppStoreConnectView {
    var confirmationMessage: String {
        let groups = selectedLocaleGroups
        let screenshotCount = groups.reduce(0) { $0 + $1.screenshotCount }
        let localeCount = groups.count
        let setCount = selectedUploadPlanEntries.count
        let shotNoun = screenshotCount == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let setNoun = setCount == 1 ? String(localized: "set") : String(localized: "sets")
        let locNoun = localeCount == 1 ? String(localized: "locale") : String(localized: "locales")
        return String(localized: "Existing screenshots in each matching display type set will be deleted and replaced. ") +
            String(localized: "\(screenshotCount) \(shotNoun) will be uploaded across \(setCount) \(setNoun) and \(localeCount) \(locNoun). ") +
            String(localized: "This cannot be undone.")
    }

    // MARK: - Header / footer

    var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            Text("Upload to App Store Connect")
                .font(.headline)
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    var demoModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Demo Mode")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text("Sample apps and a simulated upload. Nothing is sent to App Store Connect.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue)
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
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Show the full failure text, preferring the detailed report and falling back to the
    /// short banner message. Shared by the macOS footer and the iPad error banner.
    func presentErrorDetails(fallback message: String) {
        presentedErrorDetails = ASCUploadFailureDetailItem(message: errorDetailsText ?? message)
    }

    @ViewBuilder
    var backButton: some View {
        switch step {
        case .pickingVersion, .editingMetadata, .configuringPlan:
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
            Button("Cancel Upload", role: .cancel) { cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    /// The forward primary action for the four pre-upload steps (Next / Continue / Upload),
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
            ForwardPrimary(titleKey: "Next", action: { Task { await moveToMetadata() } },
                           isEnabled: canAdvanceFromVersion && !isBusy)
        case .editingMetadata:
            ForwardPrimary(titleKey: hasMetadataChanges ? "Save & Continue" : "Continue",
                           action: { Task { await saveMetadataAndContinue() } },
                           isEnabled: !isBusy)
        case .configuringPlan:
            ForwardPrimary(titleKey: "Upload", action: { isConfirmingUpload = true },
                           isEnabled: canStartUpload && !isBusy)
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

    var hasMetadataChanges: Bool {
        if copyrightDraft != originalCopyright { return true }
        if versionDrafts.contains(where: \.isChanged) { return true }
        if appInfoDrafts.contains(where: \.isChanged) { return true }
        return false
    }

    var canAdvanceFromVersion: Bool {
        guard let version = selectedVersion else { return false }
        return version.isEditable
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
        default: break
        }
    }

    func cancelUpload() {
        uploadTask?.cancel()
    }

    var validationIssues: [ASCUploadIssue] {
        guard let version = selectedVersion else { return [] }
        let raw = ASCUploadValidator.validate(version: version, plans: rowPlans)
        guard credentials.isDemoMode else { return raw }
        // In demo mode the upload is simulated, so per-row App Store rules (size
        // match, 3–10 screenshot count, duplicate target, locale matching) become
        // advisory warnings instead of hard blockers — the wizard must run end-to-end
        // for any project. Structural issues (no rows / no enabled rows / version
        // not editable) keep their original severity.
        return raw.map { $0.scope == nil ? $0 : $0.with(severity: .warning) }
    }

    var canStartUpload: Bool {
        !validationIssues.hasErrors
    }

    var uploadPlanEntries: [UploadPlanEntry] {
        rowPlans.flatMap { plan -> [UploadPlanEntry] in
            guard plan.isEnabled else { return [] }
            let rowLabel = plan.rowLabel.isEmpty ? String(localized: "Row") : plan.rowLabel
            let sourceSizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"
            let displayTypeLabel = plan.selectedDisplayType?.label ?? String(localized: "No display type selected")
            let displayTypeRawValue = plan.selectedDisplayType?.appStoreConnectValue ?? "none"

            return plan.localeTargets.flatMap { target -> [UploadPlanEntry] in
                func entry(idSuffix: String, appStoreLocaleCode: String?, isSelected: Bool, skipReason: String?) -> UploadPlanEntry {
                    UploadPlanEntry(
                        id: "\(plan.id.uuidString)-\(target.id.uuidString)\(idSuffix)",
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
                if target.isEnabled, plan.selectedDisplayType != nil, !selectedCandidates.isEmpty {
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
                } else if plan.selectedDisplayType == nil {
                    skipReason = String(localized: "No display type selected")
                } else {
                    skipReason = String(localized: "No App Store locale selected")
                }
                return [entry(idSuffix: "", appStoreLocaleCode: nil, isSelected: false, skipReason: skipReason)]
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
            entry.appStoreLocaleCode ?? entry.projectLocaleCode
        }
        return grouped.keys.sorted().map { code in
            let groupEntries = grouped[code] ?? []
            let label = groupEntries.first.map { "\($0.projectLocaleLabel) -> \(code)" } ?? code
            return UploadLocaleGroup(id: code, label: label, entries: groupEntries)
        }
    }
}
