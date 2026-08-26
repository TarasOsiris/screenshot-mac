import SwiftUI

struct ProjectLoadingOverlay: View {
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    var body: some View {
        ZStack {
            ModalScrim()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                // The detail line changes per phase; a floor stops the card twitching wider and
                // narrower as it does.
                .frame(minWidth: 180)
            }
            .padding(UIMetrics.Spacing.modal)
            .modifier(OverlayCardChrome())
        }
    }
}

/// The overlay driven by a project open. Reads `progress` here rather than at the host so the
/// phase transitions of an open invalidate this view instead of the whole editor shell's body.
struct ProjectOpenOverlay: View {
    let progress: ProjectOpenProgress

    var body: some View {
        if progress.isOpening {
            ProjectLoadingOverlay(title: progress.title, detail: progress.detail)
        }
    }
}
