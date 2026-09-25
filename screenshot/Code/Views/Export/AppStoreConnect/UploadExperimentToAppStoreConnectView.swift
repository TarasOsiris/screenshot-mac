import SwiftUI

struct UploadExperimentToAppStoreConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var state
    @State private var model = ASCExperimentFlowModel()
    @State private var presentedErrorDetails: UploadFailureDetail?
    @State private var confirming: ExperimentAction?

    private enum ExperimentAction: Identifiable {
        case upload, submit, start
        var id: Self { self }
    }

    var body: some View {
        let issues = model.step == .configuring && !model.isSelectedExperimentLocked ? model.issues : []
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
        .sheet(item: $presentedErrorDetails) { details in
            UploadFailureDetailsSheet(details: details.message)
        }
        .confirmationDialog(
            confirming.map(confirmTitle) ?? "",
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            titleVisibility: .visible,
            presenting: confirming
        ) { action in
            switch action {
            case .upload: Button("Upload Treatments", role: .destructive) { model.startUpload() }
            case .submit: Button("Submit for Review") { Task { await model.submitForReview() } }
            case .start: Button("Start Experiment") { Task { await model.startExperiment() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            confirmMessage(action)
        }
    }

    private func confirmTitle(_ action: ExperimentAction) -> LocalizedStringKey {
        switch action {
        case .upload: "Upload A/B test to App Store Connect?"
        case .submit: "Submit experiment for review?"
        case .start: "Start the experiment?"
        }
    }

    private func confirmMessage(_ action: ExperimentAction) -> Text {
        switch action {
        case .upload:
            Text(model.uploadSummary)
        case .submit:
            Text("This submits the screenshots already in App Store Connect. If you changed rows since the last upload, upload first. Its screenshots can't change while it's in review.")
        case .start:
            Text("App Store visitors in the test start seeing the treatments now. A running experiment can only be stopped in App Store Connect.")
        }
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
            if model.testableVariants.isEmpty {
                // A warning here, not a blocker: you may be back only to start an experiment you uploaded before.
                Section {
                    UploadIssuesPanel(issues: [ASCExperimentPlanner.noVariantsIssue(hasVariants: !model.variants.isEmpty).with(severity: .warning)])
                }
            }
            if model.apps.isEmpty && model.errorMessage != nil {
                Section {
                    Button("Try Again") { Task { await model.loadApps() } }
                        .disabled(model.isBusy)
                }
            }
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
            if model.isSelectedExperimentLocked {
                experimentSection
                if let experiment = model.selectedExperiment {
                    Section {
                        Text(experiment.guidance)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if !issues.isEmpty {
                    Section { UploadIssuesPanel(issues: issues) }
                }
                experimentSection
                treatmentsSection
                languagesSection
            }
        }
        .formStyle(.grouped)
    }

    private var experimentSection: some View {
        Section {
            Picker("Upload to", selection: Binding(
                get: { model.selectedExperimentId },
                set: { id in Task { await model.selectExperiment(id) } }
            )) {
                Text("New Experiment").tag(String?.none)
                ForEach(model.experiments) { experiment in
                    Text("\(experiment.name) — \(experiment.statusText)").tag(Optional(experiment.id))
                }
            }
            if let experiment = model.selectedExperiment {
                LabeledContent("Status", value: experiment.statusText)
                experimentActions(for: experiment)
            } else {
                TextField("Name", text: $model.newExperimentName)
                Picker("Visitors in the test", selection: $model.trafficProportion) {
                    ForEach([25, 50, 75, 100], id: \.self) { percent in
                        Text(verbatim: "\(percent)%").tag(percent)
                    }
                }
            }
        } header: {
            Text("Experiment")
        } footer: {
            if model.selectedExperiment == nil {
                Text("The share of App Store visitors who take part, split evenly between the Original and each treatment. The rest always see the Original.")
            }
        }
    }

    /// Start and Open stay reachable after the upload session that made the experiment is gone.
    @ViewBuilder
    private func experimentActions(for experiment: ASCExperiment, prominentSubmit: Bool = false) -> some View {
        HStack {
            if experiment.state.isEditable && !model.existingTreatments.isEmpty {
                Button("Submit for Review…") { confirming = .submit }
                    .buttonStyle(ProminenceButtonStyle(isProminent: prominentSubmit))
            }
            if experiment.canStart {
                Button("Start Experiment…") { confirming = .start }
                    .buttonStyle(.borderedProminent)
            }
            if let url = model.appStoreConnectURL {
                Button("Open in App Store Connect") { openURL(url) }
            }
        }
        .disabled(model.isBusy)
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
                    Text((rowsByVariant[variant.id] ?? []).map(\.displayLabel).joined(separator: ", "))
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
                        Text(locale.flagLabel)
                        Text(ascLocales.joined(separator: ", "))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(locale.flagLabel)
                        Text("Not on your product page")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 14) {
            UploadCompleteHeader(title: "Treatments uploaded")
            if let experiment = model.selectedExperiment {
                Text("“\(experiment.name)” now has ^[\(model.uploadedScreenshotCount) screenshot](inflect: true).")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                LabeledContent("Status", value: experiment.statusText)
                    .fixedSize()
                Text(experiment.guidance)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                if !model.leftoverNotes.isEmpty {
                    UploadIssuesPanel(issues: model.leftoverNotes.map {
                        UploadIssue(
                            severity: .warning,
                            message: $0,
                            hint: String(localized: "They're part of the test until you remove them in App Store Connect.")
                        )
                    })
                    .frame(maxWidth: 520)
                }
                experimentActions(for: experiment, prominentSubmit: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private func footer(issues: [UploadIssue]) -> some View {
        UploadWizardFooterBar(error: model.errorMessage.map { message in
            UploadWizardErrorSlot(message: message, showDetails: model.errorDetailsText.map { details in
                { presentedErrorDetails = UploadFailureDetail(message: details) }
            })
        }) {
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
                if model.isSelectedExperimentLocked {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Upload Treatments…") { confirming = .upload }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.canUpload(given: issues))
                }
            case .uploading:
                Button("Cancel") { model.cancel() }
            case .done:
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Bordered, or bordered-prominent: `.buttonStyle` can't take a conditional of two different style types.
private struct ProminenceButtonStyle: PrimitiveButtonStyle {
    let isProminent: Bool

    func makeBody(configuration: Configuration) -> some View {
        if isProminent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}
