import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Upgrade to Pro")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                featureRow("Unlimited projects")
                featureRow("Unlimited rows per project")
                featureRow("Unlimited screenshots per row")
            }
            .padding(.vertical, 4)

            PurchaseButtons(store: store)
        }
        .padding(32)
        .frame(width: 320)
        .onChange(of: store.isProUnlocked) { _, unlocked in
            if unlocked { dismiss() }
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.body)
            Text(text)
        }
    }
}

#Preview("Paywall") {
    PaywallView()
        .environment(StoreService())
}

struct PurchaseButtons: View {
    let store: StoreService

    var body: some View {
        VStack(spacing: 12) {
            if let product = store.proProduct {
                Button {
                    Task { await store.purchase() }
                } label: {
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 200)
                    } else {
                        Text("Buy Pro — \(product.displayPrice)")
                            .frame(width: 200)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isLoading)
            } else if store.didFinishLoadingProducts {
                Text("Product unavailable. Please try again later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Loading...")
                    .controlSize(.small)
            }

            Button("Restore Purchase") {
                Task { await store.restore() }
            }
            .buttonStyle(.link)
            .disabled(store.isLoading)
            .font(.caption)

            if let error = store.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if let info = store.purchaseInfo {
                Text(info)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
