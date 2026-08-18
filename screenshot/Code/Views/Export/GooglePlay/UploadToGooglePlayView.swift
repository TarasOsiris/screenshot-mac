#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Wizard for uploading screenshots to a Google Play store listing. Mirrors the App Store
/// Connect upload, but the Play flow is simpler: the user supplies a package name (no
/// app/version/metadata steps), picks an image type + languages per row, then the edit is
/// staged as a draft (`changesNotSentForReview`).
struct UploadToGooglePlayView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state

    /// Steps, package name, plan, progress and errors all live here. See GPUploadFlowModel.
    @State var model = GPUploadFlowModel()

    // View-local presentation state only.
    @State var collapsedRowPlanIds: Set<UUID> = []   // absent = expanded (default)
    @State var presentedErrorDetails: UploadFailureDetail?

    var body: some View {
        shell
            .task {
                model.bind(document: state)
                model.prefillPackageName()
            }
            .onDisappear { model.tearDown() }
            .sheet(item: $presentedErrorDetails) { details in
                UploadFailureDetailsSheet(details: details.message)
            }
    }

    @ViewBuilder
    private var shell: some View {
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

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 22))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Upload to Google Play")
                    .font(.headline)
                Text(stepSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepSubtitle: String {
        switch model.step {
        case .enteringPackage: return String(localized: "Enter the app's package name")
        case .configuringPlan: return String(localized: "Choose what to upload")
        case .uploading: return String(localized: "Uploading screenshots…")
        case .done: return String(localized: "All done")
        }
    }

    private var demoModeBanner: some View {
        DemoModeBanner(message: "A simulated upload against sample data. Nothing is sent to Google Play.")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .enteringPackage: packageStep
        case .configuringPlan: planStep
        case .uploading: uploadingStep
        case .done: doneStep
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if model.step == .configuringPlan {
                Button("Back") { model.goBack() }
                    .disabled(model.isBusy)
            }

            if let errorMessage = model.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    if model.errorDetailsText != nil {
                        Button("Details") {
                            presentedErrorDetails = UploadFailureDetail(message: model.errorDetailsText ?? errorMessage)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Spacer()

            footerPrimaryActions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var footerPrimaryActions: some View {
        switch model.step {
        case .enteringPackage:
            Button("Cancel") { dismiss() }
            Button("Continue") { model.continueToPlan() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinueFromPackage)
        case .configuringPlan:
            Button("Cancel") { dismiss() }
            Button("Upload to Google Play") { Task { await model.startUpload() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.validationIssues.hasErrors)
        case .uploading:
            Button("Cancel Upload", role: .destructive) {
                model.uploadTask?.cancel()
            }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var canContinueFromPackage: Bool {
        if model.credentials.isDemoMode { return true }
        guard model.credentials.isConfigured else { return false }
        return GooglePlayUploadValidator.isValidPackageName(
            model.packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
