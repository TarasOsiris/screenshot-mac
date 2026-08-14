import SwiftUI

struct ASCScreenshotReviewChangesView: View {
    let coordinator: ASCScreenshotSyncCoordinator
    let refresh: () -> Void

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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Review Changes")
                            .font(.title2.bold())
                        Text("Only included, changed sets will be synced. Exact checksum matches are preserved.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Review expires \(plan.expiresAt, style: .relative)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button(action: refresh) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(coordinator.phase == .applying)
                }

                if plan.sets.isEmpty {
                    Label("No compatible screenshot sets were found.", systemImage: "rectangle.stack.badge.minus")
                        .foregroundStyle(.secondary)
                } else if plan.changedSets.isEmpty {
                    Label("App Store Connect already matches the proposed screenshots.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.green.opacity(0.08), in: .rect(cornerRadius: 10))
                }

                ForEach(plan.sets) { set in
                    ASCScreenshotSetDiffCard(
                        set: set,
                        isIncluded: coordinator.selectedSetIds.contains(set.id),
                        onIncludedChange: { coordinator.toggle(set, included: $0) }
                    )
                }
            }
            .padding(16)
        }
    }
}

private struct ASCScreenshotSetDiffCard: View {
    let set: ASCScreenshotSetDiff
    let isIncluded: Bool
    let onIncludedChange: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(set.versionLabel)
                        .font(.headline)
                    Text("\(set.localeLabel) · \(set.displayType.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle(
                    "Include set",
                    isOn: Binding(
                        get: { isIncluded },
                        set: { included in onIncludedChange(included) }
                    )
                )
                    .toggleStyle(.switch)
                    .disabled(!set.isChanged || !set.canApply)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { statusSummaries }
                VStack(alignment: .leading, spacing: 6) { statusSummaries }
            }
            .accessibilityElement(children: .combine)

            screenshotStrip(title: "Current App Store", items: set.currentAssets, proposed: false)
            screenshotStrip(title: "Proposed Screenshot Bro", items: set.proposedAssets, proposed: true)

            if set.currentAssets.contains(where: { $0.remoteAsset?.previewError != nil }) {
                Label("Some current screenshots could not be previewed. They are shown as placeholders; refresh to retry.", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !set.issues.isEmpty || !set.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(set.issues + set.warnings, id: \.self) { note in
                        Label(note, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !set.canApply {
                        Text("This set cannot be included because required App Store data is unavailable.")
                            .font(.caption.bold())
                    }
                }
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.07), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isIncluded ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.18), lineWidth: isIncluded ? 2 : 1)
        }
    }

    private func statusSummary(_ status: ASCScreenshotDiffStatus, count: Int) -> some View {
        Label("\(count) \(status.label)", systemImage: status.icon)
            .font(.caption)
            .foregroundStyle(status.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private var statusSummaries: some View {
        statusSummary(.unchanged, count: set.unchangedCount)
        statusSummary(.moved, count: set.moveCount)
        statusSummary(.new, count: set.uploadCount)
        statusSummary(.removed, count: set.removalCount)
    }

    private func screenshotStrip(title: LocalizedStringKey, items: [ASCScreenshotDiffItem], proposed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.bold())
            if items.isEmpty {
                Text("Empty set")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(items) { item in
                            ASCScreenshotDiffThumbnail(
                                item: item,
                                proposed: proposed,
                                onPreview: previewURL(for: item, proposed: proposed).map { _ in
                                    { preview(item, in: items, proposed: proposed) }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.visible)
            }
        }
    }

    private func previewURL(for item: ASCScreenshotDiffItem, proposed: Bool) -> URL? {
        proposed ? item.localAsset?.fileURL : item.remoteAsset?.previewFileURL
    }

    private func preview(
        _ selectedItem: ASCScreenshotDiffItem,
        in items: [ASCScreenshotDiffItem],
        proposed: Bool
    ) {
        let previewableItems = items.compactMap { item -> (id: String, url: URL)? in
            guard let url = previewURL(for: item, proposed: proposed) else { return nil }
            return (item.id, url)
        }
        guard let selectedIndex = previewableItems.firstIndex(where: { $0.id == selectedItem.id }) else {
            return
        }
        QuickLookCoordinator.shared.preview(
            imagesAt: previewableItems.map { $0.url },
            startingAt: selectedIndex
        )
    }
}

private struct ASCScreenshotDiffThumbnail: View {
    let item: ASCScreenshotDiffItem
    let proposed: Bool
    let onPreview: (() -> Void)?

    @ViewBuilder
    var body: some View {
        if let onPreview {
            Button(action: onPreview) {
                content
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Quick Look")
        } else {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 5) {
            Group {
                if proposed, let data = item.localAsset?.previewData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else if !proposed, let data = item.remoteAsset?.previewData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.exclamationmark")
                        Text("Preview unavailable")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(width: 116, height: 150)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 7))
            .clipShape(.rect(cornerRadius: 7))

            HStack(spacing: 4) {
                Text("#\((proposed ? item.proposedIndex : item.originalIndex).map { $0 + 1 } ?? 0)")
                    .monospacedDigit()
                Image(systemName: item.status.icon)
                Text(item.status.label)
            }
            .font(.caption2.bold())
            .foregroundStyle(item.status.color)
        }
        .frame(width: 116)
    }

    private var accessibilityDescription: String {
        let index = (proposed ? item.proposedIndex : item.originalIndex).map { $0 + 1 } ?? 0
        let source = proposed ? String(localized: "Proposed") : String(localized: "Current App Store")
        return "\(source) screenshot \(index), \(item.status.label)"
    }
}

private extension ASCScreenshotDiffStatus {
    var label: String {
        switch self {
        case .unchanged: String(localized: "Unchanged")
        case .moved: String(localized: "Moved")
        case .new: String(localized: "New")
        case .removed: String(localized: "Removed")
        }
    }

    var icon: String {
        switch self {
        case .unchanged: "checkmark.circle.fill"
        case .moved: "arrow.left.arrow.right.circle.fill"
        case .new: "plus.circle.fill"
        case .removed: "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .unchanged: .green
        case .moved: .blue
        case .new: .mint
        case .removed: .orange
        }
    }
}
