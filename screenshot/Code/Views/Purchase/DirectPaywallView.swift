#if DIRECT_DISTRIBUTION
import RevenueCat
import SwiftUI

/// RevenueCatUI's paywall sells through StoreKit, which a Developer ID build can't use — so the
/// direct build sends buyers to web checkout and unlocks via the redemption link it returns.
struct DirectPaywallView: View {
    @Bindable var store: PurchaseService
    @State private var pastedLink = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Screenshot Bro Pro", systemImage: "sparkles")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Close") { store.dismissPaywall() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                ProFeatureRow(text: "Unlimited projects")
                ProFeatureRow(text: "Unlimited rows per project")
                ProFeatureRow(text: "Unlimited screenshots per row")
            }

            VStack(alignment: .leading, spacing: 6) {
                Button {
                    store.buyOnWeb()
                } label: {
                    Text("Buy Pro — One-Time Purchase")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Checkout opens in your browser. When it's done, click **Open Screenshot Bro** to activate Pro on this Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Already bought? Paste the activation link from your receipt email.")
                    .font(.callout)
                HStack {
                    TextField(text: $pastedLink, prompt: Text(verbatim: "rc-…://redeem_web_purchase?…")) {
                        Text("Activation link")
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(redeemPastedLink)
                    Button("Activate", action: redeemPastedLink)
                        .disabled(pastedURL == nil || store.isRedeeming)
                }
                if store.isRedeeming {
                    ProgressView().controlSize(.small)
                }
            }

            if let message = store.purchaseStatusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(store.purchaseStatusIsError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var pastedURL: URL? {
        URL(string: pastedLink.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.asWebPurchaseRedemption == nil ? nil : $0 }
    }

    private func redeemPastedLink() {
        guard let url = pastedURL else { return }
        Task {
            await store.redeem(url)
            pastedLink = ""
        }
    }
}
#endif
