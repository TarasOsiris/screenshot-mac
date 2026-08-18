import SwiftUI

/// Outcome of a "Test Connection" tap in a store's settings pane.
enum StoreConnectionTestResult {
    case success(String)
    case failure(String)

    /// Both panes derived this identically from an optional result, so it lives here.
    var passed: Bool {
        if case .success = self { return true }
        return false
    }
}

/// The tinted result row shown under the Test Connection button.
///
/// Both store settings panes declared this identically, down to every padding value.
struct StoreConnectionFeedbackRow: View {
    let result: StoreConnectionTestResult

    var body: some View {
        switch result {
        case .success(let message):
            row(message, symbol: "checkmark.circle.fill", tint: .green)
        case .failure(let message):
            row(message, symbol: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private func row(_ message: String, symbol: String, tint: Color) -> some View {
        Label(message, systemImage: symbol)
            .foregroundStyle(tint)
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
