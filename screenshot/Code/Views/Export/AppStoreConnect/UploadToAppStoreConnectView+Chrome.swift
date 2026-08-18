import SwiftUI

extension UploadToAppStoreConnectView {
    var confirmationMessage: String {
        if isConfirmingReviewedSync {
            model.screenshotSync.confirmationSummary
        } else {
            directUploadConfirmationMessage
        }
    }

    var directUploadConfirmationMessage: String {
        let plan = model.planEntries
        let screenshotCount = plan.screenshotCount
        let localeCount = plan.localeCount
        let versionCount = plan.versionCount
        let setCount = plan.selected.count
        let screenshotNoun = screenshotCount == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let setNoun = setCount == 1 ? String(localized: "set") : String(localized: "sets")
        let localeNoun = localeCount == 1 ? String(localized: "locale") : String(localized: "locales")
        let versionNoun = versionCount == 1 ? String(localized: "version") : String(localized: "versions")
        return String(localized: "\(screenshotCount) \(screenshotNoun) will be safely synced across \(setCount) \(setNoun), \(localeCount) \(localeNoun), and \(versionCount) \(versionNoun). Exact checksum matches will be preserved.")
    }

    // MARK: - Header / footer

    var flowTitle: LocalizedStringKey {
        model.mode == .metadata ? "Update App Store Metadata" : "Sync App Store Screenshots"
    }

    var header: some View {
        HStack {
            Image(systemName: model.mode == .metadata ? "text.badge.checkmark" : "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            Text(flowTitle)
                .font(.headline)
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
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
            if let errorMessage = model.errorMessage {
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
        presentedErrorDetails = UploadFailureDetail(message: model.errorDetailsText ?? message)
    }

    @ViewBuilder
    var backButton: some View {
        switch model.step {
        case .pickingVersion, .editingMetadata, .configuringPlan, .reviewingChanges:
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.isBusy)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    var dismissButton: some View {
        switch model.step {
        case .uploading:
            Button("Cancel Sync", role: .cancel) { cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(model.screenshotSync.phase == .applying)
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

    /// The forward button for the *current* step. Deliberately not parameterised: it
    /// always reflects `model.step`.
    var forwardPrimary: ForwardPrimary? {
        switch model.step {
        case .pickingApp:
            ForwardPrimary(titleKey: "Next", action: { Task { await model.moveToVersion() } },
                           isEnabled: model.selectedApp != nil && !model.isBusy)
        case .pickingVersion:
            ForwardPrimary(titleKey: "Next", action: { Task { await model.moveToMetadata() } },
                           isEnabled: canAdvanceFromVersion && !model.isBusy)
        case .editingMetadata:
            ForwardPrimary(titleKey: metadataPrimaryTitle,
                           action: { Task { await model.saveMetadataAndContinue() } },
                           isEnabled: !model.isBusy)
        case .configuringPlan:
            ForwardPrimary(titleKey: "Upload", action: { requestDirectUpload() },
                           isEnabled: model.canStartUpload && !model.isBusy)
        case .reviewingChanges:
            ForwardPrimary(titleKey: "Sync Selected Sets", action: { requestReviewedSync() },
                           isEnabled: model.screenshotSync.canApply && !model.isBusy)
        case .uploading, .done:
            nil
        }
    }

    @ViewBuilder
    var primaryButton: some View {
        if let primary = forwardPrimary {
            Button(primary.titleKey, action: primary.action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!primary.isEnabled)
        }
    }

    @ViewBuilder
    var reviewChangesButton: some View {
        if model.step == .configuringPlan {
            Button("Review Changes", action: model.startScreenshotReviewBuild)
                .disabled(!model.canStartUpload || model.isBusy)
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
        switch (model.mode, hasMetadataChanges) {
        case (.metadata, true): "Save"
        case (.metadata, false): "Done"
        case (.screenshots, true): "Save & Continue"
        case (.screenshots, false): "Continue"
        }
    }

    var hasMetadataChanges: Bool {
        if model.copyrightByVersion.contains(where: { $0.value != (model.originalCopyrightByVersion[$0.key] ?? "") }) { return true }
        if model.versionDrafts.contains(where: \.isChanged) { return true }
        if model.appInfoDrafts.contains(where: \.isChanged) { return true }
        return false
    }

    var canAdvanceFromVersion: Bool {
        !model.selectedVersions.isEmpty && model.selectedVersions.allSatisfy { $0.isSelectable(for: model.mode) }
    }

    func cancelUpload() {
        model.uploadTask?.cancel()
    }

}
