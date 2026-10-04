import SwiftUI

#if os(macOS)
struct PurchaseSettingsPane: View {
    @Environment(PurchaseService.self) private var store

    var body: some View {
        Form {
            Section {
                PurchasePlanRows(store: store)
            }

            purchaseStatusSection

            if store.isProUnlocked {
                ProIncludedSection()

                Section("Purchase Status") {
                    Label("Screenshot Bro Pro is unlocked.", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                    Text(purchaseManagedByText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                FreeTierSections(store: store)
            }

            LegalLinksSection()
        }
        .formStyle(.grouped)
    }

    private var purchaseManagedByText: LocalizedStringKey {
        switch DistributionChannel.current {
        case .appStore: "Your unlock is managed by the App Store for this Apple Account."
        case .direct: "Your unlock comes from a web purchase activated on this Mac."
        }
    }

    @ViewBuilder
    private var purchaseStatusSection: some View {
        if let configurationIssue = store.configurationIssue {
            Section("RevenueCat") {
                Label(configurationIssue, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        if let purchaseStatusMessage = store.purchaseStatusMessage {
            Section("Status") {
                Label(
                    purchaseStatusMessage,
                    systemImage: store.purchaseStatusIsError
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(store.purchaseStatusIsError ? .red : .secondary)
            }
        }
    }
}
#endif
