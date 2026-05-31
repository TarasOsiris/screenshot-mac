import SwiftUI

struct AppRootView: View {
    static let windowID = "main"

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
            // Declare a minimum and let the content fill any larger size. Without an
            // explicit fill frame, the window's zoom (double-click title bar) standard
            // frame is derived from the content's *fitting* size, which collapses when
            // rows are collapsed — making the window shrink/flicker or, with every row
            // collapsed, vanish entirely. Pinning a min + flexible max keeps zoom stable.
            .frame(minWidth: 820, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
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
