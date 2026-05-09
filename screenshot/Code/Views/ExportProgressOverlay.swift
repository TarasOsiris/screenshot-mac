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
                    .controlSize(.small)
            }
            .padding(UIMetrics.Spacing.modal)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        }
    }
}
