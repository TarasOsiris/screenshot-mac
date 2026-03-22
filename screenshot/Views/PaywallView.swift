import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(StoreService.self) private var store
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                paywallHeader

                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(paywallFeatures) { feature in
                        ProFeatureCard(feature: feature)
                    }
                }

                ProPurchaseCard(store: store, style: .hero)
            }
            .padding(28)
        }
        .frame(minWidth: 520, idealWidth: 560, maxWidth: 620, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: store.isProUnlocked) { _, unlocked in
            if unlocked {
                dismiss()
            }
        }
    }

    private var paywallHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Screenshot Bro Pro", systemImage: "star.circle.fill")
                .font(.headline)
                .foregroundStyle(.yellow)

            Text(store.paywallContext.title)
                .font(.system(size: 28, weight: .bold))

            Text(store.paywallContext.message)
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Free includes 1 project, \(StoreService.freeMaxRows) rows per project, and \(StoreService.freeMaxTemplatesPerRow) screenshots per row.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var paywallFeatures: [ProFeature] {
        [
            ProFeature(
                icon: "folder.badge.plus",
                title: "Unlimited projects",
                message: "Create and duplicate as many screenshot sets as you need."
            ),
            ProFeature(
                icon: "rectangle.grid.1x2.fill",
                title: "Unlimited rows",
                message: "Keep adding sections for every feature, locale, or campaign."
            ),
            ProFeature(
                icon: "square.grid.3x3.topleft.filled",
                title: "Unlimited screenshots",
                message: "Build more variants in each row without hitting a cap."
            ),
            ProFeature(
                icon: "creditcard.trianglebadge.exclamationmark",
                title: "Secure checkout",
                message: "Payments and restores handled by the App Store."
            )
        ]
    }
}

#Preview("Paywall") {
    PaywallView()
        .environment(StoreService())
}

struct ProPurchaseCard: View {
    enum Style {
        case hero
        case compact
    }

    @Environment(\.dismiss) private var dismiss

    let store: StoreService
    let style: Style

    private var productTitle: String {
        store.proProduct?.displayName ?? "Screenshot Bro Pro"
    }

    private var productDescription: String {
        let description = store.proProduct?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if description.isEmpty {
            return "Unlock the full editor with a single App Store purchase."
        }
        return description
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if style == .hero {
                VStack(alignment: .leading, spacing: 10) {
                    purchaseFactRow("Purchase type", value: "One-time in-app purchase")
                    purchaseFactRow("Unlock", value: "Current Apple Account")
                    purchaseFactRow("Restore", value: "Available anytime on another Mac")
                }

                Divider()
            }

            if let product = store.proProduct {
                pricingBlock(for: product)
            } else if store.didFinishLoadingProducts {
                unavailableBlock
            } else {
                loadingBlock
            }

            PurchaseStatusStack(store: store)

            purchaseButtons

            if style == .hero {
                Text("Payments are handled by the App Store. If you already bought Screenshot Bro Pro with this Apple Account, choose Restore Purchase.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(style == .hero ? 22 : 18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(productTitle)
                    .font(style == .hero ? .title3.weight(.semibold) : .headline)
                Spacer(minLength: 12)
                if store.isProUnlocked {
                    Label("Unlocked", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }

            if style == .hero {
                Text(productDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Text("Single App Store purchase. No subscription.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pricingBlock(for product: Product) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(product.displayPrice)
                    .font(.system(size: style == .hero ? 34 : 28, weight: .bold, design: .rounded))
                Text("one-time purchase")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            if style == .hero {
                Text("No subscription and no recurring billing.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var unavailableBlock: some View {
        Label("Product information is currently unavailable. Try again later.", systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(.orange)
    }

    private var loadingBlock: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("Loading App Store pricing…")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private var purchaseButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let operation = store.activeOperation {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(operation.progressTitle)
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }

            Group {
                if style == .hero {
                    HStack(spacing: 10) {
                        primaryPurchaseButton

                        Button("Restore Purchase") {
                            Task { await store.restore() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isLoading)

                        Button("Not Now") {
                            dismiss()
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 10) {
                        primaryPurchaseButton

                        Button("Restore") {
                            Task { await store.restore() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(store.isLoading)
                    }
                }
            }
        }
    }

    private var primaryPurchaseButton: some View {
        Button {
            Task { await store.purchase() }
        } label: {
            if let product = store.proProduct {
                Text(store.isProUnlocked ? "Already Unlocked" : "Unlock Pro for \(product.displayPrice)")
                    .frame(maxWidth: .infinity)
            } else {
                Text("Unlock Pro")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(style == .hero ? .large : .regular)
        .disabled(store.isLoading || store.proProduct == nil || store.isProUnlocked)
    }

    private func purchaseFactRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct PurchaseStatusStack: View {
    let store: StoreService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = store.purchaseError {
                PurchaseStatusRow(
                    text: error,
                    systemImage: "exclamationmark.triangle.fill",
                    tint: .red
                )
            }

            if let info = store.purchaseInfo {
                PurchaseStatusRow(
                    text: info,
                    systemImage: "info.circle.fill",
                    tint: .secondary
                )
            }
        }
    }
}

private struct PurchaseStatusRow: View {
    let text: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label {
            Text(text)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.footnote)
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProFeatureCard: View {
    let feature: ProFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: feature.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(feature.title)
                .font(.headline)

            Text(feature.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ProFeature: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
}
