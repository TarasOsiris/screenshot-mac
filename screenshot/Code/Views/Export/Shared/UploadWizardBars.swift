import SwiftUI

/// The title bar both upload wizards show above their step content: store glyph, flow title, the
/// current step in a subtitle, and the busy spinner every step shares.
struct UploadWizardHeader: View {
    let systemImage: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: String
    let isBusy: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isBusy {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The failure a wizard footer shows inline, with the full report one button away.
struct UploadWizardErrorSlot {
    let message: String
    /// nil when there is no longer report to show than the message itself.
    let showDetails: (() -> Void)?
}

/// The bar under a wizard's step content: Back on the left, the current failure beside it, and the
/// step's own actions on the right.
struct UploadWizardFooterBar<Leading: View, Actions: View>: View {
    let error: UploadWizardErrorSlot?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            leading()
            if let error {
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let showDetails = error.showDetails {
                    Button("Details", action: showDetails)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
            Spacer()
            actions()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// The iPad counterpart of the footer's error slot: a full-width banner above the step content.
struct UploadWizardErrorBanner: View {
    let error: UploadWizardErrorSlot

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error.message)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let showDetails = error.showDetails {
                Button("Details", action: showDetails)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}

/// The forward action for the step a wizard is on — "Next", "Upload", "Sync Selected Sets".
///
/// One description drives two presentations: the macOS footer's primary button and the iPad
/// navigation bar's confirmation action, so their titles, actions and enabled rules cannot drift.
/// `nil` on the terminal uploading/done screens, which have no forward action.
struct UploadForwardPrimary {
    let titleKey: LocalizedStringKey
    let action: () -> Void
    let isEnabled: Bool
}
