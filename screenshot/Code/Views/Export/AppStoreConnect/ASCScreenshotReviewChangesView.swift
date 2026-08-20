import SwiftUI

struct ASCScreenshotReviewChangesView: View {
    let coordinator: ASCScreenshotSyncCoordinator
    let refresh: () -> Void

    @State private var expandedGroupIds: Set<String> = []
    @State private var expandedSetIds: Set<String> = []
    @State private var showsUnchanged = false

    var body: some View {
        Group {
            switch coordinator.phase {
            case .loading:
                loadingView
            case .stale:
                staleView
            default:
                if let plan = coordinator.plan {
                    review(plan)
                } else {
                    emptyView
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Preparing screenshot comparison…")
                .font(.headline)
            Text(coordinator.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var staleView: some View {
        stateView(
            icon: "arrow.clockwise.circle",
            title: "Review is out of date",
            message: coordinator.errorMessage ?? "The project or App Store screenshots changed after this comparison was created.",
            actionTitle: "Refresh Changes",
            action: refresh
        )
    }

    private var emptyView: some View {
        stateView(
            icon: "photo.on.rectangle.angled",
            title: "No comparison available",
            message: "Return to the plan and review the screenshots again.",
            actionTitle: "Refresh Changes",
            action: refresh
        )
    }

    private func stateView(
        icon: String,
        title: LocalizedStringKey,
        message: String,
        actionTitle: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func review(_ plan: ASCScreenshotSyncPlan) -> some View {
        VStack(spacing: 0) {
            ASCScreenshotReviewToolbar(
                outline: coordinator.outline,
                totals: coordinator.selectionTotals,
                expiresAt: plan.expiresAt,
                isBusy: coordinator.phase == .applying,
                showsUnchanged: $showsUnchanged,
                onSelectAll: coordinator.selectAllChanged,
                onDeselectAll: coordinator.deselectAll,
                onRefresh: refresh
            )
            Divider()
            sectionList(plan)
        }
        .onAppear { seedExpansion() }
        .onChange(of: plan.id) { seedExpansion() }
    }

    private func sectionList(_ plan: ASCScreenshotSyncPlan) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                if plan.sets.isEmpty {
                    Label("No compatible screenshot sets were found.", systemImage: "rectangle.stack.badge.minus")
                        .foregroundStyle(.secondary)
                } else if coordinator.outline.changedCount == 0 {
                    Label("App Store Connect already matches the proposed screenshots.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 10))
                }

                ForEach(coordinator.outline.versions) { version in
                    Section {
                        ForEach(version.devices) { group in
                            deviceGroup(group)
                        }
                    } header: {
                        versionHeader(version)
                    }
                }
            }
            .padding(16)
        }
    }

    private func versionHeader(_ version: ASCScreenshotReviewVersionSection) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(version.versionLabel)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(version.changedCount) of \(version.setCount) sets changed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(.background)
    }

    private func deviceGroup(_ group: ASCScreenshotReviewDeviceGroup) -> some View {
        ASCScreenshotReviewDeviceGroupView(
            group: group,
            visibleSets: showsUnchanged ? group.sets : group.sets.filter(\.isChanged),
            includedSetIds: coordinator.selectedSetIds,
            expandedSetIds: expandedSetIds,
            isExpanded: expandedGroupIds.contains(group.id),
            onToggleExpanded: { toggle(&expandedGroupIds, group.id) },
            onToggleSetExpanded: { toggle(&expandedSetIds, $0.id) },
            onIncludedChange: { coordinator.toggle($0, included: $1) }
        )
    }

    private func toggle(_ ids: inout Set<String>, _ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        }
    }

    /// Groups with something to act on start open; the rest stay folded away. Re-seeded after a
    /// refresh because the sets behind the old ids are gone.
    private func seedExpansion() {
        expandedSetIds = []
        expandedGroupIds = Set(
            coordinator.outline.versions
                .flatMap(\.devices)
                .filter { $0.changedCount > 0 }
                .map(\.id)
        )
    }
}
