import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - Content by step

    @ViewBuilder
    var content: some View {
        stepContent(for: model.step)
    }

    @ViewBuilder
    func stepContent(for step: ASCUploadStep) -> some View {
        if !model.credentials.isConfigured {
            missingCredentialsView
        } else {
            Group {
                switch model.step {
                case .pickingApp: pickAppView
                case .pickingVersion: pickVersionView
                case .editingMetadata: editMetadataView
                case .configuringPlan: configurePlanView
                case .reviewingChanges: reviewChangesView
                case .uploading, .done: uploadProgressView
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { issuesBanner }
        }
    }

    /// A safe-area inset rather than a sibling above the scroll view: the sheet is a fixed height,
    /// so a sibling appearing shortens the viewport and the scroll offset re-clamps — the jump this
    /// banner's previous two placements both had. An inset leaves the frame alone and moves the
    /// content inset instead. The opaque background is load-bearing; `CalloutBox` is translucent.
    @ViewBuilder
    private var issuesBanner: some View {
        if model.step == .configuringPlan, !model.validationIssues.isEmpty {
            VStack(spacing: 0) {
                UploadIssuesPanel(issues: model.validationIssues) { model.apply($0) }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.background)
                Divider()
            }
        }
    }

    var missingCredentialsView: some View {
        StoreMissingCredentialsView(
            title: "App Store Connect API key required",
            message: "Add your Issuer ID, Key ID, and .p8 key in Settings → App Store Connect.",
            target: .appStoreConnect
        )
    }

    var pickAppView: some View {
        ASCAppSelectionStepView(
            mode: model.mode,
            appsWithVersions: model.appsWithVersions,
            selectedApp: $model.selectedApp,
            hideNonUploadable: $hideNonUploadable
        )
    }

    var pickVersionView: some View {
        ASCVersionSelectionStepView(
            mode: model.mode,
            selectedApp: model.selectedApp,
            versions: model.versions,
            versionCreation: versionCreation,
            selectedVersionIds: $model.selectedVersionIds
        )
    }

    var editMetadataView: some View {
        ASCMetadataEditorView(model: model)
    }

    var configurePlanView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let app = model.selectedApp {
                    ASCAppHeaderView(
                        app: app,
                        subtitle: model.selectedVersions.count == 1
                            ? (model.selectedVersion.map { "Version \($0.attributes.versionString) · \($0.attributes.displayState)" } ?? "")
                            : "\(model.selectedVersions.count) selected versions"
                    )
                }

                Text("Configure screenshot sync")
                    .font(.headline)

                uploadSummaryPanel

                ForEach(model.destinationPlansBinding) { $destination in
                    ASCDestinationPlanSection(
                        destination: $destination,
                        expandedRowPlanIds: $expandedRowPlanIds,
                        displayTypeDetailsPlanId: $displayTypeDetailsPlanId,
                        localeCreation: localeCreation(for: destination),
                        remoteScreenshotCounts: model.remoteScreenshotCounts,
                        rowIssues: model.listingConsistencyIssues(for: destination),
                        onFix: { model.apply($0) }
                    )
                }
            }
            .padding(16)
        }
    }

    var uploadSummaryPanel: some View {
        ASCUploadSummaryPanel(
            plan: model.planEntries,
            issues: model.validationIssues,
            isExpanded: $isPreflightExpanded,
            isBusy: model.isBusy,
            onRefresh: refreshAppStoreData
        )
    }

    var reviewChangesView: some View {
        ASCScreenshotReviewChangesView(
            coordinator: model.screenshotSync,
            refresh: { model.startScreenshotReviewRefresh() }
        )
    }

    private func refreshAppStoreData() {
        Task { await model.refreshLocalizations() }
    }

    private var versionCreation: ASCVersionCreationContext {
        ASCVersionCreationContext(
            platforms: model.platformsAwaitingAVersion,
            creatingPlatform: model.creatingVersionPlatform,
            errorMessage: model.versionCreationError,
            suggestedVersionString: { model.suggestedVersionString(platform: $0) },
            create: { platform, versionString in
                Task { await model.createAppStoreVersion(platform: platform, versionString: versionString) }
            }
        )
    }

    private func localeCreation(for destination: ASCDestinationPlan) -> ASCLocaleCreationContext {
        let versionId = destination.id
        return ASCLocaleCreationContext(
            versionId: versionId,
            // The same predicate version selection uses: a localization we can't then upload
            // screenshots to is worth nothing here.
            versionAcceptsNewLocales: destination.version.isScreenshotUploadable,
            existingStoreLocaleCodes: model.existingStoreLocaleCodes(versionId: versionId),
            inFlightKeys: model.creatingLocaleKeys,
            errors: model.localeCreationErrors,
            create: { projectLocaleCode in
                Task {
                    await model.createAppStoreLocalization(
                        projectLocaleCode: projectLocaleCode,
                        versionId: versionId
                    )
                }
            }
        )
    }

    @ViewBuilder
    var uploadProgressView: some View {
        Group {
            if model.step == .done {
                doneView
            } else {
                inProgressView
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var inProgressView: some View {
        UploadProgressView(progress: model.uploadProgress)
    }

    @ViewBuilder
    var doneView: some View {
        if model.mode == .metadata {
            metadataSavedView
        } else {
            uploadDoneView
        }
    }

    @ViewBuilder
    var uploadDoneView: some View {
        VStack(spacing: 14) {
            UploadCompleteHeader(title: "Screenshot sync complete")
            if let summary = model.uploadSummary {
                Text(screenshotSyncSummary(summary))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                appStoreConnectLink(appId: summary.appId, appName: summary.appName)
            }
        }
    }

    @ViewBuilder
    var metadataSavedView: some View {
        VStack(spacing: 14) {
            UploadCompleteHeader(title: "Metadata updated")
            if let summary = model.metadataSummary {
                if summary.fieldCount == 0 {
                    Text("No changes to save.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(metadataSavedSummary(summary))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                appStoreConnectLink(appId: summary.appId, appName: summary.appName)
            }
        }
    }

    @ViewBuilder
    func appStoreConnectLink(appId: String?, appName: String) -> some View {
        if let appId, let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)/appstore") {
            Link(destination: url) {
                Label("Open \(appName) in App Store Connect", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
        }
    }

    private func screenshotSyncSummary(_ summary: ASCUploadSummary) -> String {
        switch (summary.totalScreenshots == 1, summary.localizationCount == 1, summary.versionCount == 1) {
        case (true, true, true):
            String(localized: "1 screenshot synced across 1 locale and 1 version.")
        case (true, true, false):
            String(localized: "1 screenshot synced across 1 locale and \(summary.versionCount) versions.")
        case (true, false, true):
            String(localized: "1 screenshot synced across \(summary.localizationCount) locales and 1 version.")
        case (true, false, false):
            String(localized: "1 screenshot synced across \(summary.localizationCount) locales and \(summary.versionCount) versions.")
        case (false, true, true):
            String(localized: "\(summary.totalScreenshots) screenshots synced across 1 locale and 1 version.")
        case (false, true, false):
            String(localized: "\(summary.totalScreenshots) screenshots synced across 1 locale and \(summary.versionCount) versions.")
        case (false, false, true):
            String(localized: "\(summary.totalScreenshots) screenshots synced across \(summary.localizationCount) locales and 1 version.")
        case (false, false, false):
            String(localized: "\(summary.totalScreenshots) screenshots synced across \(summary.localizationCount) locales and \(summary.versionCount) versions.")
        }
    }

    private func metadataSavedSummary(_ summary: ASCMetadataSaveSummary) -> String {
        switch (summary.fieldCount == 1, summary.localeCount == 1, summary.versionCount == 1) {
        case (true, true, true):
            String(localized: "1 field saved across 1 locale and 1 version.")
        case (true, true, false):
            String(localized: "1 field saved across 1 locale and \(summary.versionCount) versions.")
        case (true, false, true):
            String(localized: "1 field saved across \(summary.localeCount) locales and 1 version.")
        case (true, false, false):
            String(localized: "1 field saved across \(summary.localeCount) locales and \(summary.versionCount) versions.")
        case (false, true, true):
            String(localized: "\(summary.fieldCount) fields saved across 1 locale and 1 version.")
        case (false, true, false):
            String(localized: "\(summary.fieldCount) fields saved across 1 locale and \(summary.versionCount) versions.")
        case (false, false, true):
            String(localized: "\(summary.fieldCount) fields saved across \(summary.localeCount) locales and 1 version.")
        case (false, false, false):
            String(localized: "\(summary.fieldCount) fields saved across \(summary.localeCount) locales and \(summary.versionCount) versions.")
        }
    }
}
