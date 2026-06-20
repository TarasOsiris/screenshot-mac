#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

/// Wizard for uploading screenshots to a Google Play store listing. Mirrors the App Store
/// Connect upload, but the Play flow is simpler: the user supplies a package name (no
/// app/version/metadata steps), picks an image type + languages per row, then the edit is
/// staged as a draft (`changesNotSentForReview`). DEBUG-only.
struct UploadToGooglePlayView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var state

    @State var step: Step = .enteringPackage
    @State var packageName: String = ""
    /// When off (default), the edit is committed with `changesNotSentForReview=true` so changes
    /// stage as a draft. On, they are submitted to Google Play review on commit.
    @State var sendForReview: Bool = false
    @State var rowPlans: [GPRowPlan] = []
    @State var collapsedRowPlanIds: Set<UUID> = []   // absent = expanded (default)
    @State var uploadProgress: GPUploadProgress?
    @State var uploadTask: Task<Void, Never>?
    @State var uploadSummary: UploadSummary?

    @State var errorMessage: String?
    @State var errorDetailsText: String?
    @State var presentedErrorDetails: GPUploadFailureDetailItem?
    @State var isBusy = false
    @State var credentials = GooglePlayCredentialsStore.shared

    struct UploadSummary {
        let totalScreenshots: Int
        let languageCount: Int
        let packageName: String
        /// What actually happened on commit (the draft flag may be rejected → sent to review).
        let sentForReview: Bool
    }

    enum Step: Hashable {
        case enteringPackage
        case configuringPlan
        case uploading
        case done
    }

    struct GPRowPlan: Identifiable {
        let id: UUID
        var rowLabel: String
        var rowSize: CGSize
        var templateCount: Int
        var isEnabled: Bool
        var detectedImageType: GPImageType
        var selectedImageType: GPImageType
        var localeTargets: [GPLocaleTarget]
        var inferredStorePlatform: StorePlatform?
    }

    struct GPLocaleTarget: Identifiable {
        let id = UUID()
        var appLocaleCode: String
        var appLocaleLabel: String
        var playLanguageCode: String
        var isEnabled: Bool
    }

    var validationIssues: [GPUploadIssue] {
        GooglePlayUploadValidator.validate(
            packageName: packageName,
            plans: rowPlans,
            isDemoMode: credentials.isDemoMode
        )
    }

    var body: some View {
        shell
            .task { prefillPackageName() }
            .sheet(item: $presentedErrorDetails) { details in
                GPUploadFailureDetailsSheet(details: details.message)
            }
    }

    @ViewBuilder
    private var shell: some View {
        VStack(spacing: 0) {
            header
            if credentials.isDemoMode {
                demoModeBanner
            }
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        #if os(macOS)
        .frame(width: 860, height: 680)
        #endif
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
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var stepSubtitle: String {
        switch step {
        case .enteringPackage: return String(localized: "Enter the app's package name")
        case .configuringPlan: return String(localized: "Choose what to upload")
        case .uploading: return String(localized: "Uploading screenshots…")
        case .done: return String(localized: "All done")
        }
    }

    private var demoModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
            Text("Demo mode — no screenshots are sent to Google Play.")
                .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.blue.opacity(0.12))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .enteringPackage: packageStep
        case .configuringPlan: planStep
        case .uploading: uploadingStep
        case .done: doneStep
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if step == .configuringPlan {
                Button("Back") { step = .enteringPackage }
                    .disabled(isBusy)
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    if errorDetailsText != nil {
                        Button("Details") {
                            presentedErrorDetails = GPUploadFailureDetailItem(message: errorDetailsText ?? errorMessage)
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
        switch step {
        case .enteringPackage:
            Button("Cancel") { dismiss() }
            Button("Continue") { continueToPlan() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canContinueFromPackage)
        case .configuringPlan:
            Button("Cancel") { dismiss() }
            Button("Upload to Google Play") { Task { await startUpload() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isBusy || validationIssues.hasErrors)
        case .uploading:
            Button("Cancel Upload", role: .destructive) {
                uploadTask?.cancel()
            }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
    }

    private var canContinueFromPackage: Bool {
        if credentials.isDemoMode { return true }
        guard credentials.isConfigured else { return false }
        return GooglePlayUploadValidator.isValidPackageName(
            packageName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

struct GPUploadFailureDetailItem: Identifiable {
    let id = UUID()
    let message: String
}

struct GPUploadFailureDetailsSheet: View {
    let details: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upload error details")
                .font(.headline)
            ScrollView {
                Text(details)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
    }
}
