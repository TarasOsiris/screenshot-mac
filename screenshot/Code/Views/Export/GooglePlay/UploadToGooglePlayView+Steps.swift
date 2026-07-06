import SwiftUI

extension UploadToGooglePlayView {

    // MARK: - Package step

    @ViewBuilder
    var packageStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !credentials.isConfigured {
                    notConfiguredCallout
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Package name")
                        .font(.headline)
                    Text("The application ID of the app on Google Play, e.g. com.example.myapp.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TextField("com.example.myapp", text: $packageName)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                        .frame(maxWidth: 360)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(isOn: $sendForReview) {
                        Text("Send changes to review")
                            .fontWeight(.medium)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    if sendForReview {
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
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var notConfiguredCallout: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Connect a Google service account first.")
                    .fontWeight(.medium)
                Text("Open Settings → Google Play and import your service account JSON key, or turn on demo mode.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Plan step

    @ViewBuilder
    var planStep: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                preflightPanel
                if rowPlans.isEmpty {
                    Text("This project has no rows to upload.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach($rowPlans) { $plan in
                        rowPlanCard($plan)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var preflightPanel: some View {
        let issues = validationIssues
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                let total = plannedScreenshotCount
                Text("\(total) \(total == 1 ? "screenshot" : "screenshots") to upload")
                    .font(.headline)
                Spacer()
                if issues.hasErrors {
                    Label("Fix required", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.severity.tint)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(issue.scope.map { "\($0): \(issue.message)" } ?? issue.message)
                                if let hint = issue.hint {
                                    Text(hint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func rowPlanCard(_ plan: Binding<GPRowPlan>) -> some View {
        let id = plan.wrappedValue.id
        let isCollapsed = collapsedRowPlanIds.contains(id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    if isCollapsed { collapsedRowPlanIds.remove(id) } else { collapsedRowPlanIds.insert(id) }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.wrappedValue.rowLabel.isEmpty ? "Row" : plan.wrappedValue.rowLabel)
                        .fontWeight(.medium)
                    Text("\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height)) · \(plan.wrappedValue.templateCount) \(plan.wrappedValue.templateCount == 1 ? "screenshot" : "screenshots")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if plan.wrappedValue.inferredStorePlatform == .apple {
                        Text("Looks like an iOS row")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Toggle("Include", isOn: plan.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if !isCollapsed && plan.wrappedValue.isEnabled {
                Divider()
                imageTypePicker(plan)
                Divider()
                languageTargets(plan)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .opacity(plan.wrappedValue.isEnabled ? 1 : 0.55)
    }

    @ViewBuilder
    private func imageTypePicker(_ plan: Binding<GPRowPlan>) -> some View {
        HStack(spacing: 10) {
            Text("Upload as")
                .foregroundStyle(.secondary)
            Picker("Upload as", selection: plan.selectedImageType) {
                ForEach(GPImageType.userSelectableCases) { type in
                    Text(type.label).tag(type)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 220)
            if plan.wrappedValue.selectedImageType == plan.wrappedValue.detectedImageType {
                Text("(detected)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .font(.callout)
    }

    @ViewBuilder
    private func languageTargets(_ plan: Binding<GPRowPlan>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Languages")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach(plan.localeTargets) { $target in
                HStack(spacing: 8) {
                    Toggle(isOn: $target.isEnabled) {
                        Text(target.appLocaleLabel)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    Spacer()
                    Text(target.playLanguageCode)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var plannedScreenshotCount: Int {
        rowPlans.reduce(0) { acc, plan in
            guard plan.isEnabled else { return acc }
            let langs = plan.localeTargets.filter(\.isEnabled).count
            return acc + plan.templateCount * langs
        }
    }

    // MARK: - Uploading step

    @ViewBuilder
    var uploadingStep: some View {
        VStack(spacing: 16) {
            Spacer()
            if let progress = uploadProgress, progress.totalSteps > 0 {
                ProgressView(value: Double(progress.completedSteps), total: Double(progress.totalSteps))
                    .frame(maxWidth: 360)
                Text("\(progress.completedSteps) / \(progress.totalSteps)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(progress.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ProgressView()
                Text("Preparing…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    // MARK: - Done step

    @ViewBuilder
    var doneStep: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Upload complete")
                .font(.title3.weight(.semibold))
            if let summary = uploadSummary {
                Text("\(summary.totalScreenshots) \(summary.totalScreenshots == 1 ? "screenshot" : "screenshots") across \(summary.languageCount) \(summary.languageCount == 1 ? "language" : "languages")")
                    .foregroundStyle(.secondary)
                if summary.sentForReview {
                    Text("Sent to Google Play. Review and publish from the Play Console (changes won't go live until you publish).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Saved as a draft — not sent for review. Send for review from the Play Console when ready.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let url = playConsoleURL(packageName: summary.packageName) {
                    Link("Open in Play Console", destination: url)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }

    private func playConsoleURL(packageName: String) -> URL? {
        guard !packageName.isEmpty else { return nil }
        return URL(string: "https://play.google.com/console/")
    }
}
