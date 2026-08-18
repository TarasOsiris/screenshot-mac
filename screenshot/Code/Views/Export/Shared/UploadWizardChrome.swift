import SwiftUI

// The parts of the two store wizards that do the same job. They had drifted apart in ways nobody
// chose: the demo banner was white-on-solid-blue for App Store Connect and a blue tint for Google
// Play, only one failure sheet could copy its details (and the other hard-sized itself for a Mac
// window, so it presented wrong on iPad), and the progress views disagreed on whether to show a
// label before or after the counter.

/// One line of a failure report, identified so it can drive a `ForEach`.
struct UploadFailureDetail: Identifiable {
    let id = UUID()
    let message: String
}

/// The raw technical report behind a failed upload — long, monospaced and copyable, because its
/// audience is whoever has to paste it into a bug report.
struct UploadFailureDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView(.vertical) {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.platformTextBackground)

            Divider()

            HStack {
                Button("Copy Details") {
                    PlatformPasteboard.copyString(details)
                }
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        #if os(macOS)
        .frame(width: 760, height: 520)
        #else
        .presentationDetents([.large])
        #endif
    }
}

struct DemoModeBanner: View {
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "theatermasks.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 1) {
                Text("Demo Mode")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.blue)
    }
}

/// Determinate while the service reports step counts, indeterminate before the first one lands.
struct UploadProgressView: View {
    let progress: UploadProgress?

    var body: some View {
        VStack(spacing: 16) {
            if let progress, progress.totalSteps > 0 {
                ProgressView(value: Double(progress.completedSteps), total: Double(progress.totalSteps))
                    .frame(maxWidth: 360)
                Text("\(progress.completedSteps) / \(progress.totalSteps)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(progress.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ProgressView()
                Text("Preparing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The go/no-go badge on a preflight panel. Both wizards showed the same two states with
/// different symbols (`xmark.circle.fill` vs `xmark.octagon.fill`).
struct PreflightStatusLabel: View {
    let hasErrors: Bool
    let font: Font

    var body: some View {
        if hasErrors {
            Label("Fix required", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(font)
        } else {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(font)
        }
    }
}

/// The green check and headline every "done" screen opens with; the summary below it is
/// per-store and stays in the wizard.
struct UploadCompleteHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 56))
            .foregroundStyle(.green)
        Text(title)
            .font(.title3.weight(.semibold))
    }
}
