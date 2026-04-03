import SwiftUI

struct AppRootView: View {
    @Environment(StoreService.self) private var store
    @State private var purchaseStatusDialogMessage: String?

    private var purchaseStatusAlertBinding: Binding<Bool> {
        .init(
            get: { purchaseStatusDialogMessage != nil },
            set: { if !$0 { purchaseStatusDialogMessage = nil } }
        )
    }

    var body: some View {
        ContentView()
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
