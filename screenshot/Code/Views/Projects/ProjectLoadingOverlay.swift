import SwiftUI

struct ProjectLoadingOverlay: View {
    let message: LocalizedStringKey

    var body: some View {
        ZStack {
            ModalScrim()
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
            }
            .padding(UIMetrics.Spacing.modal)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.floating))
        }
    }
}
