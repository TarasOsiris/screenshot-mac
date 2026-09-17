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
        return [
            directUploadCountSummary(
                screenshotCount: screenshotCount,
                setCount: setCount,
                localeCount: localeCount,
                versionCount: versionCount
            ),
            String(localized: "Upload compares each screenshot with the store and changes only what differs, keeping the App Store asset IDs of exact matches."),
            replaceAllExplanation(screenshotCount: screenshotCount)
        ].joined(separator: "\n\n")
    }

    private func directUploadCountSummary(
        screenshotCount: Int,
        setCount: Int,
        localeCount: Int,
        versionCount: Int
    ) -> String {
        let screenshots = screenshotCount == 1 ? String(localized: "1 screenshot") : String(localized: "\(screenshotCount) screenshots")
        let sets = setCount == 1 ? String(localized: "1 set") : String(localized: "\(setCount) sets")
        let locales = localeCount == 1 ? String(localized: "1 locale") : String(localized: "\(localeCount) locales")
        let versions = versionCount == 1 ? String(localized: "1 version") : String(localized: "\(versionCount) versions")
        return String(localized: "\(screenshots) across \(sets), \(locales), and \(versions).")
    }

    private func replaceAllExplanation(screenshotCount: Int) -> String {
        screenshotCount == 1
            ? String(localized: "Replace All Screenshots skips the comparison: everything currently in these sets is deleted and 1 screenshot is uploaded again with a new asset ID. Quicker to prepare, slower to upload.")
            : String(localized: "Replace All Screenshots skips the comparison: everything currently in these sets is deleted and all \(screenshotCount) screenshots are uploaded again with new asset IDs. Quicker to prepare, slower to upload.")
    }

    // MARK: - Header / footer

    var flowTitle: LocalizedStringKey {
        model.mode == .metadata ? "Update App Store Metadata" : "Sync App Store Screenshots"
    }

    var header: some View {
        UploadWizardHeader(
            systemImage: model.mode == .metadata ? "text.badge.checkmark" : "arrow.up.circle.fill",
            tint: .blue,
            title: flowTitle,
            subtitle: stepSubtitle,
            isBusy: model.isBusy
        )
    }

    var stepSubtitle: String {
        switch model.step {
        case .pickingApp: String(localized: "Choose the app to upload to")
        case .pickingVersion: String(localized: "Choose which versions to update")
        case .editingMetadata: String(localized: "Review the store text")
        case .configuringPlan: String(localized: "Choose what to upload")
        case .reviewingChanges: String(localized: "Review what will change")
        case .uploading: String(localized: "Syncing screenshots…")
        case .done: String(localized: "All done")
        }
    }

    var demoModeBanner: some View {
        DemoModeBanner(message: "Sample apps and a simulated screenshot sync. Nothing is sent to App Store Connect.")
    }

    var footer: some View {
        UploadWizardFooterBar(error: errorSlot) {
            backButton
        } actions: {
            dismissButton
            reviewChangesButton
            primaryButton
        }
    }

    var errorSlot: UploadWizardErrorSlot? {
        guard let errorMessage = model.errorMessage else { return nil }
        return UploadWizardErrorSlot(message: errorMessage) {
            presentErrorDetails(fallback: errorMessage)
        }
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

    /// The forward button for the *current* step. Deliberately not parameterised: it
    /// always reflects `model.step`.
    var forwardPrimary: UploadForwardPrimary? {
        switch model.step {
        case .pickingApp:
            UploadForwardPrimary(titleKey: "Next", action: { Task { await model.moveToVersion() } },
                                 isEnabled: model.selectedApp != nil && !model.isBusy)
        case .pickingVersion:
            UploadForwardPrimary(titleKey: "Next", action: { Task { await model.moveToMetadata() } },
                                 isEnabled: canAdvanceFromVersion && !model.isBusy)
        case .editingMetadata:
            UploadForwardPrimary(titleKey: metadataPrimaryTitle,
                                 action: { Task { await model.saveMetadataAndContinue() } },
                                 isEnabled: !model.isBusy)
        case .configuringPlan:
            UploadForwardPrimary(titleKey: "Upload", action: { requestDirectUpload() },
                                 isEnabled: model.canStartUpload && !model.isBusy)
        case .reviewingChanges:
            UploadForwardPrimary(titleKey: "Sync Selected Sets", action: { requestReviewedSync() },
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
