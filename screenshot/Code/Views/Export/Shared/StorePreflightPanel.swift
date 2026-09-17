import SwiftUI

/// One count on a preflight panel — screenshots, locales, versions.
struct StoreSummaryMetric: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }
}

/// The refetch action a store's preflight offers. Google Play has none — it reads nothing from the
/// store before uploading — so the slot is optional rather than a no-op button.
struct StorePreflightRefresh {
    let title: LocalizedStringKey
    let isBusy: Bool
    let action: () -> Void
}

/// The go/no-go panel at the top of a wizard's plan step: a collapsible header with the ready or
/// fix-required badge, a row of counts, and whatever breakdown the store can offer below it.
struct StorePreflightPanel<Metrics: View, Details: View>: View {
    @Binding var isExpanded: Bool
    let hasErrors: Bool
    let refresh: StorePreflightRefresh?
    @ViewBuilder var metrics: () -> Metrics
    @ViewBuilder var details: () -> Details

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if isExpanded {
                HStack(spacing: 10) {
                    metrics()
                }
                details()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            DisclosureChevronButton(expanded: isExpanded) {
                isExpanded.toggle()
            } label: {
                Text("Preflight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
            PreflightStatusLabel(hasErrors: hasErrors, font: .caption)
            if let refresh {
                Button(refresh.title, action: refresh.action)
                    .font(.caption)
                    .disabled(refresh.isBusy)
            }
        }
    }
}
