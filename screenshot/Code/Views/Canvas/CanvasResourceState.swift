import Foundation

/// Why a shape that names a resource is drawing nothing. `.satisfied` covers both "the image is
/// here" and "none was ever assigned" — only a reference the app failed to honour says anything,
/// because a device frame with no screenshot in it is otherwise a legitimate design.
enum CanvasResourceState {
    case satisfied
    case downloading
    case missing

    /// The view asks the document; the document doesn't need to know what the canvas draws.
    init(_ fileName: String?, in state: AppState) {
        guard let fileName else { self = .satisfied; return }
        if state.imageStore.pending.contains(fileName) {
            self = .downloading
        } else {
            self = state.imageStore.missing.contains(fileName) ? .missing : .satisfied
        }
    }
}
