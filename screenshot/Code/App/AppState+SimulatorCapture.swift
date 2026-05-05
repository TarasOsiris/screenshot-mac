import SwiftUI

#if DEBUG
extension AppState {
    /// Captures the currently booted iOS Simulator screen and assigns the result to
    /// `shapeId` (a device shape) using the same path as a manual image replace.
    /// The shape's existing device frame is preserved — the user has already chosen it.
    @MainActor
    func captureFromSimulator(intoShape shapeId: UUID, onError: @escaping (String) -> Void) {
        guard shapeLocation(for: shapeId) != nil else { return }
        Task { @MainActor in
            do {
                let result = try await SimulatorCaptureService.captureBooted()
                guard shapeLocation(for: shapeId) != nil else { return }
                saveImage(result.image, for: shapeId)
            } catch {
                onError(error.localizedDescription)
            }
        }
    }
}
#endif
