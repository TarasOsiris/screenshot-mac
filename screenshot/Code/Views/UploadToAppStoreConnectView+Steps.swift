import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - Content by step

    @ViewBuilder
    var content: some View {
        stepContent(for: step)
    }

    @ViewBuilder
    func stepContent(for step: Step) -> some View {
        if !credentials.isConfigured {
            missingCredentialsView
        } else {
            switch step {
            case .pickingApp: pickAppView
            case .pickingVersion: pickVersionView
            case .editingMetadata: editMetadataView
            case .configuringPlan: configurePlanView
            case .uploading, .done: uploadProgressView
            }
        }
    }

    var missingCredentialsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("App Store Connect API key required")
                .font(.headline)
            Text("Add your Issuer ID, Key ID, and .p8 key in Settings → App Store Connect.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            #if os(macOS)
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            #else
            Button {
                router.openAppStoreConnectSettings()
                dismiss()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var pickAppView: some View {
        ASCAppSelectionStepView(
            appsWithVersions: appsWithVersions,
            selectedApp: $selectedApp,
            hideNonUploadable: $hideNonUploadable
        )
    }


    var pickVersionView: some View {
        ASCVersionSelectionStepView(
            selectedApp: selectedApp,
            versions: versions,
            selectedVersion: $selectedVersion
        )
    }

    var editMetadataView: some View {
        VStack(spacing: 0) {
            if let app = selectedApp, let version = selectedVersion {
                ASCAppHeaderView(
                    app: app,
                    subtitle: "Version \(version.attributes.versionString) · \(version.attributes.displayState)"
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }

            #if os(macOS)
            HStack(alignment: .top, spacing: 0) {
                metadataLocaleSidebar
                    .frame(width: 180)
                Divider()
                metadataFormPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            #else
            metadataLocalePicker
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()
            metadataFormPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
    }

    #if os(iOS)
    /// iPad replacement for the desktop locale sidebar: a pull-down menu above the form. Each
    /// row (and the current selection) shows a change-dot mirroring the sidebar's indicators.
    var metadataLocalePicker: some View {
        Menu {
            ForEach(metadataLocaleCodes, id: \.self) { code in
                Button {
                    selectedMetadataLocale = code
                } label: {
                    if localeHasChanges(code) {
                        Label(code, systemImage: "pencil.circle.fill")
                    } else {
                        Text(code)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text(selectedMetadataLocale ?? metadataLocaleCodes.first ?? "")
                    .fontWeight(.medium)
                if let selected = selectedMetadataLocale, localeHasChanges(selected) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    #endif

    #if os(macOS)
    var metadataLocaleSidebar: some View {
        List(selection: Binding(
            get: { selectedMetadataLocale },
            set: { selectedMetadataLocale = $0 }
        )) {
            Section("Version") {
                HStack {
                    Text("All locales")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if copyrightDraft != originalCopyright {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.blue)
                    }
                }
            }
            Section("Locales") {
                ForEach(metadataLocaleCodes, id: \.self) { code in
                    HStack {
                        Text(code)
                        Spacer()
                        if localeHasChanges(code) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.blue)
                        }
                    }
                    .tag(code as String?)
                }
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    func localeHasChanges(_ code: String) -> Bool {
        if versionDrafts.contains(where: { $0.locale == code && $0.isChanged }) { return true }
        if appInfoDrafts.contains(where: { $0.locale == code && $0.isChanged }) { return true }
        return false
    }

    @ViewBuilder
    var metadataFormPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                versionCopyrightField
                if let code = selectedMetadataLocale {
                    if let idx = appInfoDrafts.firstIndex(where: { $0.locale == code }) {
                        appInfoSection(index: idx)
                    }
                    if let idx = versionDrafts.firstIndex(where: { $0.locale == code }) {
                        versionLocaleSection(index: idx)
                    }
                    if !versionDrafts.contains(where: { $0.locale == code }),
                       !appInfoDrafts.contains(where: { $0.locale == code }) {
                        Text("No editable metadata for this locale.")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } else {
                    Text("Select a locale on the left to edit its metadata.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(16)
        }
    }

    var versionCopyrightField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copyright")
                .font(.subheadline)
                .fontWeight(.semibold)
            TextField("© 2025 Your Company", text: $copyrightDraft)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)
            Text("Applies to all locales for this version.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    func appInfoSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("App Info (shared across versions)")
                .font(.subheadline)
                .fontWeight(.semibold)
            metadataField(
                label: "App Name",
                text: $appInfoDrafts[index].name,
                limit: 30
            )
            metadataField(
                label: "Subtitle",
                text: $appInfoDrafts[index].subtitle,
                limit: 30
            )
            metadataField(
                label: "Privacy Policy URL",
                text: $appInfoDrafts[index].privacyPolicyUrl,
                limit: nil,
                isURL: true
            )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    @ViewBuilder
    func versionLocaleSection(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Version")
                .font(.subheadline)
                .fontWeight(.semibold)
            metadataField(
                label: "Promotional Text",
                text: $versionDrafts[index].promotionalText,
                limit: 170,
                multiline: true,
                minHeight: 44
            )
            metadataField(
                label: "Description",
                text: $versionDrafts[index].description,
                limit: 4000,
                multiline: true,
                minHeight: 140
            )
            metadataField(
                label: "Keywords (comma-separated)",
                text: $versionDrafts[index].keywords,
                limit: 100
            )
            metadataField(
                label: "What's New",
                text: $versionDrafts[index].whatsNew,
                limit: 4000,
                multiline: true,
                minHeight: 80
            )
            if canCopyWhatsNewToOtherLocales(from: index) {
                Button("Copy to all locales") {
                    copyWhatsNewToOtherLocales(from: index)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            metadataField(
                label: "Support URL",
                text: $versionDrafts[index].supportUrl,
                limit: nil,
                isURL: true
            )
            metadataField(
                label: "Marketing URL",
                text: $versionDrafts[index].marketingUrl,
                limit: nil,
                isURL: true
            )
        }
        .padding(10)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    func canCopyWhatsNewToOtherLocales(from index: Int) -> Bool {
        guard versionDrafts.indices.contains(index) else { return false }
        let draft = versionDrafts[index]
        guard draft.locale.lowercased().hasPrefix("en") else { return false }
        guard !draft.whatsNew.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return versionDrafts.contains { $0.locale != draft.locale }
    }

    func copyWhatsNewToOtherLocales(from index: Int) {
        guard versionDrafts.indices.contains(index) else { return }
        let source = versionDrafts[index].whatsNew
        let sourceLocale = versionDrafts[index].locale
        for i in versionDrafts.indices where versionDrafts[i].locale != sourceLocale {
            versionDrafts[i].whatsNew = source
        }
    }

    @ViewBuilder
    func metadataField(
        label: LocalizedStringKey,
        text: Binding<String>,
        limit: Int?,
        multiline: Bool = false,
        minHeight: CGFloat = 0,
        isURL: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let limit {
                    Text("\(text.wrappedValue.count)/\(limit)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(text.wrappedValue.count > limit ? .red : .secondary)
                }
            }
            if multiline {
                #if os(macOS)
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .padding(4)
                    .background(Color.platformTextBackground, in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
                #else
                // iOS: a native auto-growing multi-line field rather than a hand-bordered TextEditor.
                TextField("", text: text, axis: .vertical)
                    .lineLimit(3...)
                    .textFieldStyle(.roundedBorder)
                #endif
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    #if os(iOS)
                    .keyboardType(isURL ? .URL : .default)
                    .textInputAutocapitalization(isURL ? .never : nil)
                    .autocorrectionDisabled(isURL)
                    #endif
            }
        }
    }

    var configurePlanView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let app = selectedApp, let version = selectedVersion {
                    ASCAppHeaderView(
                        app: app,
                        subtitle: "Version \(version.attributes.versionString) · \(version.attributes.displayState)"
                    )
                }

                Text("Review and upload plan")
                    .font(.headline)

                uploadSummaryPanel

                replaceWarningCallout

                issuesPanel

                ForEach($rowPlans) { $plan in
                    rowPlanCard(plan: $plan)
                }
            }
            .padding(16)
        }
    }

    var uploadSummaryPanel: some View {
        let allEntries = uploadPlanEntries
        let entries = allEntries.filter(\.isSelected)
        let skipped = allEntries.filter { !$0.isSelected }
        let groups = localeGroups(from: entries)
        let screenshotCount = entries.reduce(0) { $0 + $1.screenshotCount }
        let issues = validationIssues

        return ASCUploadSummaryPanel(
            entries: entries,
            skipped: skipped,
            groups: groups,
            screenshotCount: screenshotCount,
            issues: issues,
            isExpanded: $isPreflightExpanded,
            isBusy: isBusy,
            onRefresh: refreshAppStoreData
        )
    }

    var replaceWarningCallout: some View {
        ASCReplaceWarningCallout()
    }

    @ViewBuilder
    var issuesPanel: some View {
        ASCIssuesPanel(issues: validationIssues)
    }

    func rowPlanCard(plan: Binding<RowPlan>) -> some View {
        let expanded = !collapsedRowPlanIds.contains(plan.wrappedValue.id)
        let availableDisplayTypes = ASCDisplayType.userSelectableCases(
            forPlatform: selectedVersion?.attributes.ascPlatform
        )
        return ASCUploadRowPlanCard(
            plan: plan,
            expanded: expanded,
            availableDisplayTypes: availableDisplayTypes,
            displayTypeDetailsPlanId: $displayTypeDetailsPlanId,
            onToggleExpanded: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if expanded { collapsedRowPlanIds.insert(plan.wrappedValue.id) }
                    else { collapsedRowPlanIds.remove(plan.wrappedValue.id) }
                }
            }
        )
    }

    private func refreshAppStoreData() {
        Task { await refreshLocalizations() }
    }

    @ViewBuilder
    var uploadProgressView: some View {
        Group {
            if step == .done {
                doneView
            } else {
                inProgressView
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var inProgressView: some View {
        VStack(spacing: 16) {
            if let progress = uploadProgress {
                ProgressView(value: Double(progress.completedSteps), total: Double(max(progress.totalSteps, 1)))
                Text(progress.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(progress.completedSteps) / \(progress.totalSteps)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Upload complete")
                .font(.title3)
                .fontWeight(.semibold)
            if let summary = uploadSummary {
                Text("\(summary.totalScreenshots) screenshot\(summary.totalScreenshots == 1 ? "" : "s") uploaded across \(summary.localizationCount) locale\(summary.localizationCount == 1 ? "" : "s").")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let appId = summary.appId,
                   let url = URL(string: "https://appstoreconnect.apple.com/apps/\(appId)/appstore") {
                    Link(destination: url) {
                        Label("Open \(summary.appName) in App Store Connect", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}
