import SwiftUI

struct ExportProgressOverlay: View {
    let progress: Int
    let total: Int
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text("Exporting Screenshots...")
                    .font(.headline)
                ProgressView(value: Double(progress), total: Double(max(1, total)))
                    .frame(width: 200)
                Text("\(progress) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .compactControlSize()
            }
            .padding(UIMetrics.Spacing.modal)
            .modifier(ExportOverlayCardChrome())
        }
    }
}

/// Liquid Glass card on iOS 26+ (the card floats over the dimmed editor); material fallback elsewhere.
private struct ExportOverlayCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: UIMetrics.CornerRadius.floating))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        }
        #else
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        #endif
    }
}
