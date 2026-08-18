import SwiftUI

// Chrome shared by the App Store Connect and Google Play credential panes. The two were ~46%
// identical: the same status header, the same platform-forked Test Connection button, the same
// Remove Credentials button and confirmation, and the same demo-mode section — differing only in
// their prose, their credential fields and their links, which stay in each pane.

extension StoreCredentialsStatus {
    var symbolColor: Color {
        switch self {
        case .demoMode: .blue
        case .connected: .green
        case .readyToTest: .orange
        case .finishSetup: .secondary
        }
    }
}

/// Symbol, title and per-store message, with an optional trailing progress capsule
/// (App Store Connect shows "n of 4 complete"; Google Play has nothing to count).
struct StoreCredentialsStatusHeader: View {
    let status: StoreCredentialsStatus
    let message: String
    var progressSummary: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.symbolColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(status.title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if let progressSummary {
                Text(progressSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

/// Right-aligned and compact on macOS; full-width on iPad.
struct StoreConnectionTestButton: View {
    let isTesting: Bool
    let isEnabled: Bool
    let action: () async -> Void

    var body: some View {
        #if os(macOS)
        HStack {
            Spacer()
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!isEnabled)
        }
        #else
        button
            .buttonStyle(.borderedProminent)
            .disabled(!isEnabled)
        #endif
    }

    private var button: some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 6) {
                if isTesting { ProgressView().controlSize(.small) }
                Text(isTesting ? "Testing…" : "Test Connection")
            }
            #if !os(macOS)
            .frame(maxWidth: .infinity)
            #endif
        }
    }
}

/// The label is a parameter because the two panes word it differently today
/// ("Clear Credentials…" vs "Remove Credentials…") and this refactor doesn't change copy.
struct StoreRemoveCredentialsButton: View {
    let label: LocalizedStringKey
    @Binding var isConfirming: Bool

    var body: some View {
        #if os(macOS)
        HStack {
            Spacer()
            Button(label, role: .destructive) { isConfirming = true }
                .controlSize(.small)
        }
        #else
        Button(label, role: .destructive) { isConfirming = true }
            .frame(maxWidth: .infinity)
        #endif
    }
}

extension View {
    /// macOS confirms destructive removal with a `confirmationDialog`; iPad uses an `alert`.
    func storeCredentialsRemovalConfirmation(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        confirmLabel: LocalizedStringKey,
        isPresented: Binding<Bool>,
        onRemove: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible) {
            Button(confirmLabel, role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
        #else
        // iPad: a centered alert, not an action-sheet popover anchored to the button.
        alert(title, isPresented: isPresented) {
            Button(confirmLabel, role: .destructive, action: onRemove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
        #endif
    }
}

/// The demo-mode toggle, its active-state note, and the surrounding section.
struct StoreDemoModeSection: View {
    @Binding var isDemoMode: Bool
    let sectionTitle: LocalizedStringKey
    let toggleDescription: LocalizedStringKey
    let activeNote: LocalizedStringKey
    let footer: LocalizedStringKey

    var body: some View {
        Section {
            Toggle(isOn: $isDemoMode) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Enable demo mode")
                        .fontWeight(.medium)
                    Text(toggleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)

            if isDemoMode {
                Label(activeNote, systemImage: "info.circle.fill")
                    .foregroundStyle(.blue)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(sectionTitle)
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }
    }
}
