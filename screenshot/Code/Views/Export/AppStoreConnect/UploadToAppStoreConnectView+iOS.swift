#if os(iOS)
import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - iPad NavigationStack shell

    var iosBody: some View {
        NavigationStack(path: $path) {
            stepScreen(.pickingApp)
                .navigationDestination(for: ASCUploadStep.self) { stepScreen($0) }
        }
        .onChange(of: path) { oldPath, newPath in
            model.handlePathChange(from: oldPath, to: newPath)
        }
    }

    /// One pushed screen: optional demo banner + error banner above the step content, with a
    /// per-step nav-bar toolbar. The uploading/done screen hides Back and flips on `step`.
    @ViewBuilder
    private func stepScreen(_ stepValue: ASCUploadStep) -> some View {
        VStack(spacing: 0) {
            if model.credentials.isDemoMode {
                demoModeBanner
            }
            iosErrorBanner
            stepContent(for: stepValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(flowTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(
            stepValue == .uploading || stepValue == .done || model.screenshotSync.phase == .applying
        )
        .interactiveDismissDisabled(stepValue == .uploading)
        .toolbar { iosToolbar(for: stepValue) }
    }

    @ViewBuilder
    private var iosErrorBanner: some View {
        if let errorMessage = model.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Details") { presentErrorDetails(fallback: errorMessage) }
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08))
        }
    }

    @ToolbarContentBuilder
    private func iosToolbar(for stepValue: ASCUploadStep) -> some ToolbarContent {
        // Cancel lives on the root only; deeper screens use the system Back button.
        if stepValue == .pickingApp {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        if model.isBusy {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView().controlSize(.small)
            }
        }
        if stepValue == .configuringPlan {
            ToolbarItem(placement: .topBarTrailing) {
                reviewChangesButton
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            iosPrimaryButton(for: stepValue)
        }
    }

    /// Reuses the shared `forwardPrimary(for:)` (same titles/actions/enabled rules as the macOS
    /// footer); the terminal uploading/done screen consults the live `step` to switch
    /// Cancel Upload ↔ Close.
    @ViewBuilder
    private func iosPrimaryButton(for stepValue: ASCUploadStep) -> some View {
        if let primary = forwardPrimary(for: stepValue) {
            Button(primary.titleKey, action: primary.action)
                .disabled(!primary.isEnabled)
        } else if model.step == .done {
            Button("Close") { dismiss() }
        } else {
            Button("Cancel Sync", role: .cancel) { cancelUpload() }
        }
    }
}
#endif
