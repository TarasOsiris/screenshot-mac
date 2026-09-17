import SwiftUI

extension UploadToGooglePlayView {

    // MARK: - Package step

    @ViewBuilder
    var packageStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                packageField
                verificationStatus
                sendForReviewToggle
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var packageField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Package name")
                .font(.headline)
            Text("The application ID of the app on Google Play, e.g. com.example.myapp.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField("com.example.myapp", text: $model.packageName)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .onSubmit { Task { await model.continueToPlan() } }
                recentPackagesMenu
            }
            .frame(maxWidth: 380)
        }
    }

    @ViewBuilder
    private var recentPackagesMenu: some View {
        let recents = model.recentPackageNames
        if !recents.isEmpty {
            Menu {
                ForEach(recents, id: \.self) { name in
                    Button(name) { model.packageName = name }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    #if os(iOS)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    #endif
            }
            .menuIndicator(.hidden)
            .frame(width: 34)
            .accessibilityLabel("Recent package names")
        }
    }

    @ViewBuilder
    private var verificationStatus: some View {
        switch model.packageVerification {
        case .unverified:
            EmptyView()
        case .verifying:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking access…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .verified(let name):
            Label("\(name) is reachable by this service account.", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .fixedSize(horizontal: false, vertical: true)
        case .failed(let reason):
            CalloutBox(tint: .orange) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 480)
        }
    }

    private var sendForReviewToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $model.sendForReview) {
                Text("Send changes to review")
                    .fontWeight(.medium)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            if model.sendForReview {
                Label(
                    "Screenshots will be submitted to Google Play review when uploaded.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
            } else {
                Label(
                    "Screenshots are saved as an un-reviewed draft and never sent for review. If this app doesn't allow that (some published apps don't), the upload stops without changing anything — turn this on to send them to review instead.",
                    systemImage: "info.circle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Plan step

    @ViewBuilder
    var planStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                preflightPanel
                // Outside the panel, like App Store Connect: collapsing the preflight must not
                // hide the errors that are blocking the upload.
                UploadIssuesPanel(issues: model.validationIssues)
                if model.rowPlans.isEmpty {
                    Text("This project has no rows to upload.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($model.rowPlans) { $plan in
                        rowPlanCard($plan)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            // Play's rows carry the language toggles, so they open expanded — but only the first
            // time. Re-seeding on every appear would re-open rows the user collapsed and then
            // stepped Back and forward past. See the note on `expandedRowPlanIds`.
            guard !hasSeededRowExpansion else { return }
            hasSeededRowExpansion = true
            expandedRowPlanIds.formUnion(model.rowPlans.map(\.id))
        }
    }

    @ViewBuilder
    private var preflightPanel: some View {
        StorePreflightPanel(
            isExpanded: $isPreflightExpanded,
            hasErrors: model.validationIssues.hasErrors,
            refresh: nil
        ) {
            StoreSummaryMetric(value: "\(enabledRowCount)", label: "rows")
            StoreSummaryMetric(value: "\(plannedScreenshotCount)", label: "screenshots")
            StoreSummaryMetric(value: "\(plannedLanguageCount)", label: "languages")
        } details: {
            EmptyView()
        }
    }

    @ViewBuilder
    private func rowPlanCard(_ plan: Binding<GPRowPlan>) -> some View {
        let id = plan.wrappedValue.id
        StoreUploadRowPlanCard(
            title: plan.wrappedValue.displayLabel,
            sizeSummary: plan.wrappedValue.sizeAndCountSummary,
            foreignPlatformHint: plan.wrappedValue.inferredStorePlatform == .apple ? "Looks like an iOS row" : nil,
            isEnabled: plan.isEnabled,
            expanded: expandedRowPlanIds.contains(id),
            onToggleExpanded: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expandedRowPlanIds.contains(id) {
                        expandedRowPlanIds.remove(id)
                    } else {
                        expandedRowPlanIds.insert(id)
                    }
                }
            }
        ) {
            imageTypePicker(plan)

            Text("Languages")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(plan.localeTargets) { $target in
                languageRow($target)
            }
        }
    }

    // MARK: - Image type

    @ViewBuilder
    private func imageTypePicker(_ plan: Binding<GPRowPlan>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            imageTypeSourceRow(plan)
            imageTypeTargetRow(plan)
        }
    }

    private func imageTypeSourceRow(_ plan: Binding<GPRowPlan>) -> some View {
        HStack {
            Text("Source")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(verbatim: plan.wrappedValue.sizeLabel)
                .font(.caption)
            if plan.wrappedValue.selectedAssetType == plan.wrappedValue.detectedAssetType {
                Label("Auto-detected", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Button {
                    plan.selectedAssetType.wrappedValue = plan.wrappedValue.detectedAssetType
                } label: {
                    Label("Use detected (\(plan.wrappedValue.detectedAssetType.label))", systemImage: "wand.and.stars")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Spacer()
            imageTypeDetailsButton(plan.wrappedValue)
        }
    }

    private func imageTypeDetailsButton(_ plan: GPRowPlan) -> some View {
        Button {
            imageTypeDetailsPlanId = plan.id
        } label: {
            Image(systemName: "info.circle")
                #if os(iOS)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Details")
        .popover(isPresented: Binding(
            get: { imageTypeDetailsPlanId == plan.id },
            set: { isPresented in
                if !isPresented { imageTypeDetailsPlanId = nil }
            }
        )) {
            GPImageTypeDetailsPopover(plan: plan)
        }
    }

    private func imageTypeTargetRow(_ plan: Binding<GPRowPlan>) -> some View {
        HStack {
            Text("Upload as")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Picker("Upload as", selection: plan.selectedAssetType) {
                ForEach(GPImageType.userSelectableCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .labelsHidden()
            #if os(macOS)
            .frame(maxWidth: 340, alignment: .leading)
            #endif
            Text(plan.wrappedValue.selectedAssetType.apiValue)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Languages

    private func languageRow(_ target: Binding<GPLocaleTarget>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: target.isEnabled) {
                Text(target.wrappedValue.appLocaleLabel)
            }
            .storeSelectionToggleStyle()
            .font(.caption)
            Spacer()
            Text(target.wrappedValue.playLanguageCode)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Counts

    var enabledRowCount: Int {
        model.rowPlans.filter { $0.isEnabled && $0.localeTargets.contains(where: \.isEnabled) }.count
    }

    var plannedScreenshotCount: Int {
        model.rowPlans.reduce(0) { acc, plan in
            guard plan.isEnabled else { return acc }
            return acc + plan.templateCount * plan.localeTargets.filter(\.isEnabled).count
        }
    }

    var plannedLanguageCount: Int {
        Set(
            model.rowPlans
                .filter(\.isEnabled)
                .flatMap { $0.localeTargets.filter(\.isEnabled).map(\.playLanguageCode) }
        ).count
    }

    // MARK: - Uploading / done

    @ViewBuilder
    var uploadProgressStep: some View {
        Group {
            if model.step == .done {
                doneView
            } else {
                UploadProgressView(progress: model.uploadProgress)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            UploadCompleteHeader(title: "Upload complete")
            if let summary = model.uploadSummary {
                Text(uploadCompleteSummary(summary))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if summary.sentForReview {
                    Text("Sent to Google Play. Review and publish from the Play Console (changes won't go live until you publish).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Saved as a draft — not sent for review. Send for review from the Play Console when ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if let url = URL(string: "https://play.google.com/console/") {
                    Link("Open Play Console", destination: url)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func uploadCompleteSummary(_ summary: GPUploadSummary) -> String {
        switch (summary.totalScreenshots == 1, summary.languageCount == 1) {
        case (true, true):
            String(localized: "1 screenshot across 1 language")
        case (true, false):
            String(localized: "1 screenshot across \(summary.languageCount) languages")
        case (false, true):
            String(localized: "\(summary.totalScreenshots) screenshots across 1 language")
        case (false, false):
            String(localized: "\(summary.totalScreenshots) screenshots across \(summary.languageCount) languages")
        }
    }
}

/// Mirrors `ASCDisplayTypeDetailsPopover`. This is the only place `requirementsDescription` is
/// shown — Play's size rules were previously written down in the model and never surfaced.
private struct GPImageTypeDetailsPopover: View {
    let plan: GPRowPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Image Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text(verbatim: plan.sizeLabel)
            }
            LabeledContent("Auto-detected") {
                Text(plan.detectedAssetType.label)
            }
            LabeledContent("Upload target") {
                Text(plan.selectedAssetType.label)
            }
            LabeledContent("Play value") {
                Text(plan.selectedAssetType.apiValue)
                    .font(.caption.monospaced())
            }
            LabeledContent("Accepted sizes") {
                Text(plan.selectedAssetType.requirementsDescription)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 360)
        #else
        .frame(maxWidth: 360)
        #endif
    }
}
