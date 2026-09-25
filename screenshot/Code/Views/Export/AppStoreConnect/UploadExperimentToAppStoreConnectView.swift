import SwiftUI

struct UploadExperimentToAppStoreConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var state
    @State private var model = ASCExperimentFlowModel()

    var body: some View {
        let issues = model.step == .configuring ? model.issues : []
        UploadWizardShell {
            UploadWizardHeader(
                systemImage: "square.split.2x1.fill",
                tint: .purple,
                title: "Upload A/B Test to App Store Connect",
                subtitle: subtitle,
                isBusy: model.isBusy
            )
        } banner: {
            if model.credentials.isDemoMode {
                DemoModeBanner(message: "A sample app and a simulated experiment. Nothing is sent to App Store Connect.")
            }
        } content: {
            content(issues: issues)
        } footer: {
            footer(issues: issues)
        }
        .task {
            model.bind(document: state)
            await model.loadApps()
        }
        .onDisappear { model.tearDown() }
    }

    private var subtitle: String {
        switch model.step {
        case .pickingApp: String(localized: "Choose the app and platform to test")
        case .configuring: String(localized: "Choose the experiment and what goes into it")
        case .uploading: String(localized: "Uploading treatments…")
        case .done: String(localized: "Treatments uploaded")
        }
    }

    @ViewBuilder
    private func content(issues: [UploadIssue]) -> some View {
        if !model.credentials.isConfigured {
            StoreMissingCredentialsView(
                title: "App Store Connect API key required",
                message: "Add your Issuer ID, Key ID, and .p8 key in Settings → App Store Connect.",
                target: .appStoreConnect
            )
        } else {
            switch model.step {
            case .pickingApp: appStep
            case .configuring: configureStep(issues: issues)
            case .uploading:
                UploadProgressView(progress: model.uploadProgress)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .done: doneStep
            }
        }
    }

    // MARK: - Steps

    private var appStep: some View {
        Form {
            Picker("App", selection: $model.selectedAppId) {
                ForEach(model.apps, id: \.app.id) { entry in
                    Text(entry.app.attributes.name).tag(Optional(entry.app.id))
                }
            }
            if model.availablePlatforms.count > 1 {
                Picker("Platform", selection: $model.platform) {
                    ForEach(model.availablePlatforms, id: \.self) { platform in
                        Text(platform.displayName).tag(platform)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Text("Each variant becomes one treatment in a product page experiment. The Original rows stay on your product page as the control.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func configureStep(issues: [UploadIssue]) -> some View {
        Form {
            if !issues.isEmpty {
                Section { UploadIssuesPanel(issues: issues) }
            }
            experimentSection
            treatmentsSection
            languagesSection
        }
        .formStyle(.grouped)
    }

    private var experimentSection: some View {
        Section("Experiment") {
            Picker("Experiment", selection: Binding(
                get: { model.selectedExperimentId },
                set: { id in Task { await model.selectExperiment(id) } }
            )) {
                Text("New Experiment").tag(String?.none)
                ForEach(model.experiments) { experiment in
                    Text("\(experiment.name) — \(experiment.statusText)").tag(Optional(experiment.id))
                }
            }
            if model.selectedExperiment == nil {
                TextField("Name", text: $model.newExperimentName)
                Picker("Traffic in the test", selection: $model.trafficProportion) {
                    ForEach([25, 50, 75, 100], id: \.self) { percent in
                        Text(verbatim: "\(percent)%").tag(percent)
                    }
                }
            }
        }
    }

    private var treatmentsSection: some View {
        let rowsByVariant = model.rowsByVariant
        let testable = ASCExperimentPlanner.variantsWithRows(model.variants, rowsByVariant: rowsByVariant)
        let matches = ASCExperimentPlanner.treatmentMatches(variants: testable, existing: model.existingTreatments)
        return Section("Treatments") {
            if testable.isEmpty {
                Text("No variant has any rows yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(testable) { variant in
                LabeledContent {
                    Text(matches[variant.id] == nil ? "New treatment" : "Updates existing treatment")
                        .foregroundStyle(.secondary)
                } label: {
                    VariantBadge(name: variant.name, tint: VariantPalette.color(for: variant.id, in: model.variants))
                    Text("^[\(rowsByVariant[variant.id]?.count ?? 0) row](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var languagesSection: some View {
        let assignment = model.localeAssignment
        return Section("Languages") {
            ForEach(model.localeState.locales) { locale in
                if let ascLocales = assignment[locale.code] {
                    Toggle(isOn: Binding(
                        get: { model.enabledLocaleCodes.contains(locale.code) },
                        set: { isOn in
                            if isOn { model.enabledLocaleCodes.insert(locale.code) }
                            else { model.enabledLocaleCodes.remove(locale.code) }
                        }
                    )) {
                        LabeledContent(locale.flagLabel, value: ascLocales.joined(separator: ", "))
                    }
                } else {
                    LabeledContent(locale.flagLabel, value: String(localized: "Not on your product page"))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            UploadCompleteHeader(title: "Treatments uploaded")
            if let experiment = model.selectedExperiment {
                Text("\(model.uploadedScreenshotCount) screenshots are in “\(experiment.name)”, which is now \(experiment.statusText.lowercased()).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack {
                    if experiment.state.isEditable {
                        Button("Submit for Review") { Task { await model.submitForReview() } }
                            .buttonStyle(.borderedProminent)
                    }
                    if experiment.canStart {
                        Button("Start Experiment") { Task { await model.startExperiment() } }
                            .buttonStyle(.borderedProminent)
                    }
                    if let url = model.appStoreConnectURL {
                        Button("Open in App Store Connect") { openURL(url) }
                    }
                }
                .disabled(model.isBusy)
                Text("Results appear in App Store Connect once the experiment is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private func footer(issues: [UploadIssue]) -> some View {
        UploadWizardFooterBar(error: model.errorMessage.map { UploadWizardErrorSlot(message: $0, showDetails: nil) }) {
            if model.step == .configuring {
                Button("Back") { model.goBack() }
            }
        } actions: {
            switch model.step {
            case .pickingApp:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Continue") { Task { await model.continueToConfigure() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.selectedApp == nil || model.isBusy)
            case .configuring:
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Upload Treatments") { model.startUpload() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canUpload(given: issues))
            case .uploading:
                Button("Cancel") { model.cancel() }
            case .done:
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
