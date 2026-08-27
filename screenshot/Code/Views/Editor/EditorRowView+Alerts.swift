import SwiftUI

extension EditorRowView {
    /// Failure alerts return no buttons on purpose: SwiftUI supplies the lone dismissing
    /// OK, and `activeAlert`'s binding already clears the value on dismiss.
    @ViewBuilder
    func alertActions(for alert: RowAlert) -> some View {
        switch alert {
        case .deleteRow:
            Button("Delete", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { state.deleteRow(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        case .resetRow:
            Button("Reset", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { state.resetRow(row.id) }
            }
            Button("Cancel", role: .cancel) {}
        #if DEBUG && os(macOS)
        case .simulatorInstallPrompt(let shapeId):
            Button("Install…") { installSimulatorHelper(capturingInto: shapeId) }
            Button("Cancel", role: .cancel) {}
        #endif
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func alertMessage(for alert: RowAlert) -> some View {
        switch alert {
        case .deleteRow:
            Text("Are you sure you want to delete \"\(row.label)\"?")
        case .resetRow:
            Text("This will remove all screenshots and shapes from \"\(row.label)\" and restore default settings.")
        case .exportFailed(let message), .backgroundRemovalFailed(let message):
            Text(message)
        #if DEBUG
        case .simulatorCaptureFailed(let message):
            Text(message)
        #endif
        #if DEBUG && os(macOS)
        case .simulatorInstallPrompt:
            Text("Capturing from the iOS Simulator needs a one-time setup: a small script that asks the Simulator for a screenshot and does nothing else.\n\nBecause of macOS security, only you can install it. Click Install… to save the script — you'll only need to do this once.")
        #endif
        }
    }

    #if DEBUG && os(macOS)
    func installSimulatorHelper(capturingInto shapeId: UUID) {
        Task { @MainActor in
            switch SimulatorCaptureService.presentInstallPanel() {
            case .success:
                state.captureFromSimulator(intoShape: shapeId) { message in
                    activeAlert = .simulatorCaptureFailed(message)
                }
            case .failure(let error):
                if let message = error.errorDescription {
                    activeAlert = .simulatorCaptureFailed(message)
                }
            }
        }
    }
    #endif
}
