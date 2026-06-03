import SwiftUI

struct AppRootView: View {
    static let windowID = "main"

    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var purchaseStatusDialogMessage: String?

    private var purchaseStatusAlertBinding: Binding<Bool> {
        .init(
            get: { purchaseStatusDialogMessage != nil },
            set: { if !$0 { purchaseStatusDialogMessage = nil } }
        )
    }

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
            } else if state.hasCompletedInitialLoad {
                NoProjectView(onCreate: createProject)
            } else {
                // Initial load hasn't run yet (iCloud-deferred) — avoid flashing the empty
                // "no projects" screen over projects that are about to load in.
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.platformWindowBackground)
            }
        }
            .alert("Purchase Status", isPresented: purchaseStatusAlertBinding) {
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
