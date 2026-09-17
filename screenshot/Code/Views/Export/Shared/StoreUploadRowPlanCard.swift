import SwiftUI

/// One editor row's card on a store wizard's plan step: a disclosure header carrying the row's
/// label, size summary, include switch and cross-store hint, over whatever that store needs to
/// configure for the row.
///
/// Takes display values rather than a `StoreRowPlan` so it stays out of the generic-parameter
/// business — the stores' asset types and locale targets differ, but none of that reaches the
/// shell. Everything store-specific is `expandedContent`.
struct StoreUploadRowPlanCard<Content: View>: View {
    let title: String
    let sizeSummary: String
    /// "Looks like an Android row" on Apple's wizard and the mirror of it on Play's; nil when the
    /// row's inferred platform matches the store being uploaded to.
    let foreignPlatformHint: LocalizedStringKey?
    @Binding var isEnabled: Bool
    let expanded: Bool
    let onToggleExpanded: () -> Void
    @ViewBuilder var expandedContent: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if expanded && isEnabled {
                expandedContent()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
        .opacity(isEnabled ? 1 : 0.55)
    }

    private var header: some View {
        HStack(spacing: 6) {
            if isEnabled {
                DisclosureChevronButton(expanded: expanded, action: onToggleExpanded)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(sizeSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let foreignPlatformHint {
                    Text(foreignPlatformHint)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .accessibilityLabel("Include")
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
