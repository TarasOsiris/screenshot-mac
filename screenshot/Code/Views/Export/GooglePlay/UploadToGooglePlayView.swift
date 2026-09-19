#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Wizard for uploading screenshots to a Google Play store listing. The same shape as the App
/// Store Connect upload — same shell, header, footer, row cards and preflight — over a simpler
/// flow: Play has no app list, no versions and no metadata, so the user names a package, picks an
/// image type and languages per row, and the edit is staged as a draft
/// (`changesNotSentForReview`).
struct UploadToGooglePlayView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state
    #if os(iOS)
    @Environment(AppNavigationRouter.self) var router
    #endif

    /// Steps, package name, plan, progress and errors all live here. See GPUploadFlowModel.
    @State var model = GPUploadFlowModel()

    #if os(iOS)
    // iPad pushes a screen per step; root `.enteringPackage` is implicit.
    @State var path: [GPUploadStep] = []
    #endif

    // View-local presentation state only.
    @State var isPreflightExpanded = true
    /// Absent = collapsed. Seeded to every row on the way into the plan step: Play's language
    /// toggles are the whole point of that screen, where App Store Connect's version × row tree
    /// would be a wall if it opened expanded.
    @State var expandedRowPlanIds: Set<UUID> = []
    @State var hasSeededRowExpansion = false
    @State var presentedErrorDetails: UploadFailureDetail?
    @State var imageTypeDetailsPlanId: UUID?
    @State var isConfirmingUpload = false

    var body: some View {
        #if os(macOS)
        sharedModifiers(macBody)
        #else
        sharedModifiers(iosBody)
        #endif
    }

    private func sharedModifiers(_ content: some View) -> some View {
        content
            .task {
                model.bind(document: state)
                #if os(iOS)
                // Capture the projected Binding, not `path`: `path` is @State, so an escaping
                // closure would capture the whole view struct — including `_model`, which stores
                // these closures. See the same note in UploadToAppStoreConnectView.
                model.navigationDidAdvance = { [path = $path] in path.wrappedValue.append($0) }
                model.navigationWillRetreat = { [path = $path] in
                    if path.wrappedValue.last == .uploading || path.wrappedValue.last == .done {
                        path.wrappedValue.removeLast()
                    }
                }
                #endif
                model.prefillPackageName()
            }
            .onDisappear { model.tearDown() }
            .sheet(item: $presentedErrorDetails) { details in
                UploadFailureDetailsSheet(details: details.message)
            }
            .confirmationDialog(
                "Upload to Google Play",
                isPresented: $isConfirmingUpload,
                titleVisibility: .visible
            ) {
                Button("Upload", role: .destructive) {
                    Task { await model.startUpload() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmationMessage)
            }
    }

    #if os(macOS)
    private var macBody: some View {
        UploadWizardShell {
            header
        } banner: {
            if model.credentials.isDemoMode { demoModeBanner }
        } content: {
            content
        } footer: {
            footer
        }
    }
    #endif

    // MARK: - Header

    var header: some View {
        UploadWizardHeader(
            systemImage: "play.rectangle.on.rectangle",
            tint: .green,
            title: "Upload to Google Play",
            subtitle: stepSubtitle,
            isBusy: model.isBusy
        )
    }

    var stepSubtitle: String {
        switch model.step {
        case .enteringPackage: String(localized: "Enter the app's package name")
        case .configuringPlan: String(localized: "Choose what to upload")
        case .uploading: String(localized: "Uploading screenshots…")
        case .done: String(localized: "All done")
        }
    }

    var demoModeBanner: some View {
        DemoModeBanner(message: "A simulated upload against sample data. Nothing is sent to Google Play.")
    }

    /// Play replaces rather than reconciles — `deleteAllImages` then re-upload — so the dialog has
    /// to say so. App Store Connect's equivalent can promise it keeps matching assets; this can't.
    var confirmationMessage: String {
        let screenshots = plannedScreenshotCount == 1
            ? String(localized: "1 screenshot")
            : String(localized: "\(plannedScreenshotCount) screenshots")
        let languages = plannedLanguageCount == 1
            ? String(localized: "1 language")
            : String(localized: "\(plannedLanguageCount) languages")
        return [
            String(localized: "\(screenshots) across \(languages)."),
            String(localized: "Every screenshot currently on the listing for the selected languages and image types is deleted and replaced."),
            model.sendForReview
                ? String(localized: "The changes are sent to Google Play review when the edit is committed.")
                : String(localized: "The changes are saved as an un-reviewed draft. Send them for review from the Play Console.")
        ].joined(separator: "\n\n")
    }

    // MARK: - Content

    @ViewBuilder
    var content: some View {
        stepContent(for: model.step)
    }

    @ViewBuilder
    func stepContent(for step: GPUploadStep) -> some View {
        if !model.credentials.isConfigured {
            missingCredentialsView
        } else {
            Group {
                switch step {
                case .enteringPackage: packageStep
                case .configuringPlan: planStep
                case .uploading, .done: uploadProgressStep
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { issuesBanner(for: step) }
        }
    }

    /// See the App Store Connect wizard's `issuesBanner` for why this is an inset and not a sibling.
    @ViewBuilder
    private func issuesBanner(for step: GPUploadStep) -> some View {
        if step == .configuringPlan, !model.validationIssues.isEmpty {
            VStack(spacing: 0) {
                UploadIssuesPanel(issues: model.validationIssues)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.background)
                Divider()
            }
        }
    }

    var missingCredentialsView: some View {
        StoreMissingCredentialsView(
            title: "Google Play service account required",
            message: "Import your service account JSON key in Settings → Google Play.",
            target: .googlePlay
        )
    }

    // MARK: - Footer

    var footer: some View {
        UploadWizardFooterBar(error: errorSlot) {
            backButton
        } actions: {
            dismissButton
            primaryButton
        }
    }

    var errorSlot: UploadWizardErrorSlot? {
        guard let errorMessage = model.errorMessage else { return nil }
        return UploadWizardErrorSlot(message: errorMessage) {
            presentErrorDetails(fallback: errorMessage)
        }
    }

    func presentErrorDetails(fallback message: String) {
        presentedErrorDetails = UploadFailureDetail(message: model.errorDetailsText ?? message)
    }

    @ViewBuilder
    var backButton: some View {
        if model.step == .configuringPlan {
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.isBusy)
        }
    }

    @ViewBuilder
    var dismissButton: some View {
        switch model.step {
        case .uploading:
            Button("Cancel Upload", role: .cancel) { model.cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    /// The forward action for the current step, shared by the macOS footer and the iPad nav bar.
    var forwardPrimary: UploadForwardPrimary? {
        switch model.step {
        case .enteringPackage:
            UploadForwardPrimary(
                titleKey: "Next",
                action: { Task { await model.continueToPlan() } },
                isEnabled: canContinueFromPackage && !model.isBusy
            )
        case .configuringPlan:
            UploadForwardPrimary(
                titleKey: "Upload",
                action: { isConfirmingUpload = true },
                isEnabled: !model.isBusy && !model.validationIssues.hasErrors
            )
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

    /// The footer sits outside `content`, so it is still on screen when the step has been replaced
    /// by the missing-credentials state — and a prefilled package name would otherwise leave Next
    /// live with nothing behind it.
    var canContinueFromPackage: Bool {
        model.credentials.isConfigured
            && GooglePlayUploadValidator.isValidPackageName(
                model.packageName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
    }
}
