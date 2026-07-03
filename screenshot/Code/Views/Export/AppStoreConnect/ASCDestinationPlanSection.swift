import SwiftUI

struct ASCDestinationPlanSection: View {
    @Binding var destination: UploadToAppStoreConnectView.DestinationPlan
    @Binding var expandedRowPlanIds: Set<String>
    @Binding var displayTypeDetailsPlanId: String?

    private var platform: ASCPlatform? {
        destination.version.attributes.ascPlatform
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            ForEach($destination.rowPlans) { $plan in
                rowPlanCard(plan: $plan)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.04), in: .rect(cornerRadius: 8))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ASCPlatformBadge(
                        platform: platform,
                        fallbackName: destination.version.attributes.displayPlatform,
                        style: .iconOnly
                    )
                    Text(destination.title)
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                Text(destination.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(destination.localizations.count) locale\(destination.localizations.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func rowPlanCard(plan: Binding<UploadToAppStoreConnectView.RowPlan>) -> some View {
        let detailsId = rowPlanKey(rowId: plan.wrappedValue.id)
        let expanded = expandedRowPlanIds.contains(detailsId)
        let availableDisplayTypes = ASCDisplayType.userSelectableCases(
            forPlatform: platform
        )

        return ASCUploadRowPlanCard(
            plan: plan,
            detailsId: detailsId,
            expanded: expanded,
            availableDisplayTypes: availableDisplayTypes,
            displayTypeDetailsPlanId: $displayTypeDetailsPlanId,
            onToggleExpanded: { toggleRowPlan(detailsId: detailsId, expanded: expanded) }
        )
    }

    private func rowPlanKey(rowId: UUID) -> String {
        "\(destination.id)|\(rowId.uuidString)"
    }

    private func toggleRowPlan(detailsId: String, expanded: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if expanded {
                expandedRowPlanIds.remove(detailsId)
            } else {
                expandedRowPlanIds.insert(detailsId)
            }
        }
    }
}
