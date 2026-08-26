import SwiftUI

struct AppRootView: View {
    static let windowID = "main"

    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var state
    // macOS-only: on iPadOS \.openWindow subscribes to focused-scene churn that re-invalidated the hierarchy for seconds on first project open.
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    @State private var purchaseStatusDialogMessage: String?

    private func createProject() {
        // The macOS empty state opens the dedicated New Project window. (On iOS this branch
        // isn't reached — the Projects home owns the empty state — and there's no such scene.)
        #if os(macOS)
        openWindow(id: NewProjectWindowView.windowID)
        #endif
    }

    var body: some View {
        Group {
            if state.activeProjectId != nil {
                ContentView()
                    .screenView(.editor)
            } else if state.hasCompletedInitialLoad {
                NoProjectView(onCreate: createProject)
                    .screenView(.noProject)
            } else {
                // Initial load hasn't run yet (iCloud-deferred) — avoid flashing the empty
                // "no projects" screen over projects that are about to load in.
                ProjectLoadingOverlay(title: "Loading Projects…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformWindowBackground)
            }
        }
            .alert("Purchase Status", isPresented: $purchaseStatusDialogMessage.isPresent()) {
                Button("OK") { purchaseStatusDialogMessage = nil }
            } message: {
                Text(purchaseStatusDialogMessage ?? "")
            }
            .onChange(of: store.purchaseStatusMessage) { _, newValue in
                guard let newValue, !store.purchaseStatusIsError else { return }
                purchaseStatusDialogMessage = newValue
            }
    }
}
