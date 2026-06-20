#if os(iOS)
import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - iPad NavigationStack shell

    var iosBody: some View {
        NavigationStack(path: $path) {
            stepScreen(.pickingApp)
                .navigationDestination(for: Step.self) { stepScreen($0) }
        }
        .onChange(of: path) { oldPath, newPath in
            // Keep `step` authoritative as the system Back button pops the stack — forward
            // moves go through `advance(to:)`, but Back is driven by SwiftUI alone.
            step = newPath.last ?? .pickingApp
            // A user-initiated Back clears a stale error banner (matching macOS `goBack()`).
            // An upload error/cancel retreat pops the `.uploading`/`.done` screen *after*
            // setting `errorMessage`, so keep that one — the plan screen explains why it stopped.
            if newPath.count < oldPath.count,
               oldPath.last != .uploading, oldPath.last != .done {
                errorMessage = nil
                errorDetailsText = nil
            }
        }
    }

    /// One pushed screen: optional demo banner + error banner above the step content, with a
    /// per-step nav-bar toolbar. The uploading/done screen hides Back and flips on `step`.
    @ViewBuilder
    private func stepScreen(_ stepValue: Step) -> some View {
        VStack(spacing: 0) {
            if credentials.isDemoMode {
                demoModeBanner
            }
            iosErrorBanner
            stepContent(for: stepValue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Upload to App Store Connect")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(stepValue == .uploading || stepValue == .done)
        .interactiveDismissDisabled(stepValue == .uploading)
        .toolbar { iosToolbar(for: stepValue) }
    }

    @ViewBuilder
    private var iosErrorBanner: some View {
        if let errorMessage {
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
    private func iosToolbar(for stepValue: Step) -> some ToolbarContent {
        // Cancel lives on the root only; deeper screens use the system Back button.
        if stepValue == .pickingApp {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        if isBusy {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView().controlSize(.small)
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
    private func iosPrimaryButton(for stepValue: Step) -> some View {
        if let primary = forwardPrimary(for: stepValue) {
            Button(primary.titleKey, action: primary.action)
                .disabled(!primary.isEnabled)
        } else if step == .done {
            Button("Close") { dismiss() }
        } else {
            Button("Cancel Upload", role: .cancel) { cancelUpload() }
        }
    }
}
#endif
