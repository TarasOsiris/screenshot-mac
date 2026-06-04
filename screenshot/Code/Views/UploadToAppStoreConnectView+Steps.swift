#if os(macOS)
import SwiftUI

extension UploadToAppStoreConnectView {
    // MARK: - Content by step

    @ViewBuilder
    var content: some View {
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
            SettingsLink {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderedProminent)
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

            HStack(alignment: .top, spacing: 0) {
                metadataLocaleSidebar
                    .frame(width: 180)
                Divider()
                metadataFormPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

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
                limit: nil
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
                limit: nil
            )
            metadataField(
                label: "Marketing URL",
                text: $versionDrafts[index].marketingUrl,
                limit: nil
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
        minHeight: CGFloat = 0
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
                TextEditor(text: text)
                    .font(.body)
                    .frame(minHeight: minHeight)
                    .padding(4)
                    .background(Color.platformTextBackground, in: .rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                    )
            } else {
                TextField("", text: text)
                    .textFieldStyle(.roundedBorder)
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
        let entries = selectedUploadPlanEntries
        let screenshotCount = entries.reduce(0) { $0 + $1.screenshotCount }
        let issues = validationIssues

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                disclosureChevronButton(expanded: isPreflightExpanded, action: {
                    isPreflightExpanded.toggle()
                }) {
                    Text("Preflight")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                Spacer()
                if issues.hasErrors {
                    Label("Fix required", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
                Button("Refresh App Store data") {
                    Task { await refreshLocalizations() }
                }
                .font(.caption)
                .disabled(isBusy)
            }

            if isPreflightExpanded {
                HStack(spacing: 10) {
                    summaryMetric("\(entries.count)", "sets")
                    summaryMetric("\(screenshotCount)", "screenshots")
                    summaryMetric("\(selectedLocaleGroups.count)", "locales")
                }

                if !selectedLocaleGroups.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Selected uploads")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(selectedLocaleGroups) { group in
                            localePlanGroupRow(group)
                        }
                    }
                }

                if !skippedUploadPlanEntries.isEmpty {
                    DisclosureGroup("Skipped items (\(skippedUploadPlanEntries.count))") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(skippedUploadPlanEntries.prefix(12)) { entry in
                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Text("\(entry.projectLocaleLabel) · \(entry.rowLabel): \(entry.skipReason ?? String(localized: "Skipped"))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            if skippedUploadPlanEntries.count > 12 {
                                Text("\(skippedUploadPlanEntries.count - 12) more skipped item\(skippedUploadPlanEntries.count - 12 == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }
                    .font(.caption)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    func summaryMetric(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 78, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.04), in: .rect(cornerRadius: 6))
    }

    func localePlanGroupRow(_ group: UploadLocaleGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(group.screenshotCount) screenshot\(group.screenshotCount == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(group.entries) { entry in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(entry.rowLabel) -> \(entry.displayTypeLabel)")
                            .font(.caption)
                            .lineLimit(1)
                        Text("Source \(entry.sourceSizeLabel) · \(entry.templateCount) screenshot\(entry.templateCount == 1 ? "" : "s") · \(entry.displayTypeRawValue)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: .rect(cornerRadius: 6))
    }

    var replaceWarningCallout: some View {
        calloutBox(tint: .orange) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.orange)
                        .font(.system(size: 13))
                    Text("If a matching display type already has screenshots, they will be deleted and replaced. You'll be asked to confirm before anything is uploaded.")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    var issuesPanel: some View {
        let issues = validationIssues
        if !issues.isEmpty {
            calloutBox(tint: issues.hasErrors ? .red : .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(issues) { issue in
                        issueRow(issue)
                    }
                }
            }
        }
    }

    func calloutBox<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }

    func issueRow(_ issue: ASCUploadIssue) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity.tint)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 2) {
                issueMessageText(issue)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint = issue.hint {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    func issueMessageText(_ issue: ASCUploadIssue) -> Text {
        if let scope = issue.scope {
            return Text(scope).fontWeight(.semibold) + Text(" · ") + Text(issue.message)
        }
        return Text(issue.message)
    }

    /// Leading disclosure chevron with a comfortable hit target, shared by the collapsible sections.
    func disclosureChevronButton<Label: View>(
        expanded: Bool,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label = { EmptyView() }
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                label()
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func rowPlanCard(plan: Binding<RowPlan>) -> some View {
        let expanded = !collapsedRowPlanIds.contains(plan.wrappedValue.id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                disclosureChevronButton(expanded: expanded, action: {
                    if expanded { collapsedRowPlanIds.insert(plan.wrappedValue.id) }
                    else { collapsedRowPlanIds.remove(plan.wrappedValue.id) }
                })
                Toggle(isOn: plan.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.wrappedValue.rowLabel.isEmpty ? String(localized: "Row") : plan.wrappedValue.rowLabel)
                            .fontWeight(.medium)
                        Text("\(String(Int(plan.wrappedValue.rowSize.width)))×\(String(Int(plan.wrappedValue.rowSize.height))) · \(plan.wrappedValue.templateCount) screenshot\(plan.wrappedValue.templateCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }

            if expanded && plan.wrappedValue.isEnabled {
                displayTypePicker(plan: plan)

                Text("Locales")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(plan.localeTargets) { $target in
                    localeTargetRow(target: $target)
                }
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    func displayTypePicker(plan: Binding<RowPlan>) -> some View {
        let detected = plan.wrappedValue.detectedDisplayType
        let selected = plan.wrappedValue.selectedDisplayType
        let availableCases = ASCDisplayType.userSelectableCases(forPlatform: selectedVersion?.attributes.ascPlatform)
        let groups: [(String, [ASCDisplayType])] = [
            ("iPhone", availableCases.filter { $0.family == .iphone }),
            ("iPad", availableCases.filter { $0.family == .ipad }),
            ("Mac", availableCases.filter { $0.family == .mac }),
        ]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Source")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Text(verbatim: "\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height))")
                    .font(.caption)
                if let detected, detected == selected {
                    Label("Auto-detected", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else if let detected, detected != selected {
                    Button {
                        plan.wrappedValue.selectedDisplayType = detected
                    } label: {
                        Label("Use detected (\(detected.label))", systemImage: "wand.and.stars")
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                Spacer()
                Button {
                    displayTypeDetailsPlanId = plan.wrappedValue.id
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .popover(isPresented: Binding(
                    get: { displayTypeDetailsPlanId == plan.wrappedValue.id },
                    set: { isPresented in
                        if !isPresented { displayTypeDetailsPlanId = nil }
                    }
                )) {
                    displayTypeDetailsPopover(plan: plan.wrappedValue)
                }
            }
            HStack {
                Text("Upload as")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .leading)
                Menu {
                    Button("Select…") { plan.wrappedValue.selectedDisplayType = nil }
                    ForEach(groups, id: \.0) { (title, items) in
                        if !items.isEmpty {
                            Section(title) {
                                ForEach(items) { type in
                                    Button(type.label) { plan.wrappedValue.selectedDisplayType = type }
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text(selected?.label ?? "Select…")
                            .lineLimit(1)
                        Spacer()
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 340, alignment: .leading)
                if let selected {
                    Text(selected.appStoreConnectValue)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    func displayTypeDetailsPopover(plan: RowPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text(verbatim: "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))")
            }
            LabeledContent("Auto-detected") {
                Text(plan.detectedDisplayType?.label ?? "No exact match")
            }
            if let selected = plan.selectedDisplayType {
                LabeledContent("Upload target") {
                    Text(selected.label)
                }
                LabeledContent("ASC value") {
                    Text(selected.appStoreConnectValue)
                        .font(.caption.monospaced())
                }
                LabeledContent("Accepted sizes") {
                    Text(selected.acceptedSizeDescription)
                        .multilineTextAlignment(.trailing)
                }
                if selected.family == .ipad {
                    Label("App Store Connect rejects this if the selected app version is iPhone-only.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    func localeTargetRow(target: Binding<LocaleTarget>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: target.isEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(target.wrappedValue.appLocaleLabel)
                    Text("Project \(target.wrappedValue.appLocaleCode)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 150, alignment: .leading)
            }
            .toggleStyle(.checkbox)
            .disabled(target.wrappedValue.candidates.isEmpty)

            if target.wrappedValue.candidates.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("No matching App Store locale")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text("Add this locale in App Store Connect, then refresh locales.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("", selection: target.selectedASCLocalizationId) {
                    Text("Choose…").tag(String?.none)
                    ForEach(target.wrappedValue.candidates) { candidate in
                        Text(candidate.attributes.locale).tag(Optional(candidate.id))
                    }
                }
                .labelsHidden()
                .disabled(!target.wrappedValue.isEnabled)
                if let selectedId = target.wrappedValue.selectedASCLocalizationId,
                   let selected = target.wrappedValue.candidates.first(where: { $0.id == selectedId }) {
                    Text("-> \(selected.attributes.locale)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

#endif
