import SwiftUI

/// Non-blocking counterpart to `ProjectLoadingOverlay`: the editor is already usable while
/// screenshots decode, so this says how far along they are instead of covering the window.
///
/// Takes the progress object rather than two `Int`s so the per-batch counter updates invalidate
/// this capsule instead of `ContentView`'s body — which is the whole editor shell.
struct CanvasImageLoadingPill: View {
    let progress: ProjectOpenProgress

    var body: some View {
        Group {
            if progress.isLoadingImages {
                HStack(spacing: 8) {
                    ProgressView(value: Double(progress.imagesLoaded), total: Double(max(1, progress.imagesTotal)))
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                    Text("Loading images \(progress.imagesLoaded) of \(progress.imagesTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(UIMetrics.Stroke.subtle))
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: progress.isLoadingImages)
        .allowsHitTesting(false)
    }
}
