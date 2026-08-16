import SwiftUI

/// Shown when no project exists (first launch, or after the last project is deleted).
/// Same empty state on macOS and iPad — a large "Create Project" call to action.
struct NoProjectView: View {
    let onCreate: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Projects", systemImage: "square.on.square.dashed")
        } description: {
            Text("Create your first project to start designing screenshots.")
        } actions: {
            Button("Create Project", action: onCreate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformWindowBackground)
    }
}
