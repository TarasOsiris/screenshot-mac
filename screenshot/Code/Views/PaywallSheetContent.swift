import SwiftUI
import RevenueCatUI

struct PaywallSheetContent: View {
    @Bindable var store: StoreService

    var body: some View {
        if let configurationIssue = store.configurationIssue {
            VStack(alignment: .leading, spacing: 16) {
                Label("RevenueCat isn’t configured", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(configurationIssue)
                    .foregroundStyle(.secondary)

                Button("Close") {
                    store.dismissPaywall()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            // Fixed sizing is a macOS window concern; on iOS it fills the presenting sheet.
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 240)
            #else
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #endif
        } else {
            RevenueCatUI.PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { store.handlePurchaseCompleted($0) }
                .onRestoreCompleted { store.handleRestoreCompleted($0) }
                .onPurchaseFailure { store.handlePurchaseFailure($0) }
                .onRestoreFailure { store.handleRestoreFailure($0) }
                .onRequestedDismissal { store.dismissPaywall() }
                // macOS needs an explicit window size; on iOS the paywall fills the sheet/screen.
                #if os(macOS)
                .frame(minWidth: 520, idealWidth: 560, maxWidth: 620, minHeight: 660, idealHeight: 700)
                #endif
        }
    }
}
