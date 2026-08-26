import SwiftUI

struct ExportProgressOverlay: View {
    let progress: Int
    let total: Int
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            ModalScrim()
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
            .modifier(OverlayCardChrome())
        }
    }
}
