import AppKit
import SwiftUI

private struct ASCAppIconView: View {
    let bundleId: String
    let size: CGFloat

    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .failure, .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .task(id: bundleId) {
            iconURL = await AppStoreConnectIconFetcher.shared.iconURL(forBundleId: bundleId)
        }
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
            Image(systemName: "app.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: size * 0.45))
        }
    }
}

private struct ASCAppHeaderView: View {
    let app: ASCApp
    let subtitle: String
    var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            ASCAppIconView(bundleId: app.attributes.bundleId, size: iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.attributes.name)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ASCUploadFailureDetailItem: Identifiable {
    let id = UUID()
    let message: String
}

private struct ASCUploadFailureDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()

            ScrollView([.vertical, .horizontal]) {
                Text(details)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                Button("Copy Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(details, forType: .string)
                }
                Spacer()
                Button("OK") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 760, height: 520)
    }
}

struct UploadToAppStoreConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var state

    @State private var step: Step = .pickingApp
    @State private var apps: [ASCApp] = []
    @State private var selectedApp: ASCApp?

    @State private var versions: [ASCAppStoreVersion] = []
    @State private var selectedVersion: ASCAppStoreVersion?

    @State private var localizations: [ASCAppStoreVersionLocalization] = []

    @State private var versionDrafts: [VersionLocaleDraft] = []
    @State private var appInfoDrafts: [AppInfoLocaleDraft] = []
    @State private var copyrightDraft: String = ""
    @State private var originalCopyright: String = ""
    @State private var selectedMetadataLocale: String?

    @State private var rowPlans: [RowPlan] = []
    @State private var uploadProgress: ASCUploadProgress?
    @State private var uploadTask: Task<Void, Never>?
    @State private var uploadSummary: UploadSummary?

    @State private var errorMessage: String?
    /// Full error text (summary + API response + context). When nil, the Details button falls back to `errorMessage`.
    @State private var errorDetailsText: String?
    @State private var presentedErrorDetails: ASCUploadFailureDetailItem?
    @State private var displayTypeDetailsPlanId: UUID?
    @State private var isBusy = false
    @State private var isConfirmingUpload = false

    struct UploadSummary {
        let appId: String?
        let appName: String
        let totalScreenshots: Int
        let localizationCount: Int
    }

    @State private var credentials = AppStoreConnectCredentialsStore.shared

    private enum Step {
        case pickingApp
        case pickingVersion
        case editingMetadata
        case configuringPlan
        case uploading
        case done
    }

    struct VersionLocaleDraft: Identifiable {
        let id: String
        let locale: String
        var description: String
        var keywords: String
        var promotionalText: String
        var whatsNew: String
        var marketingUrl: String
        var supportUrl: String
        var original: ASCAppStoreVersionLocalization.Attributes

        var isChanged: Bool {
            description != (original.description ?? "")
                || keywords != (original.keywords ?? "")
                || promotionalText != (original.promotionalText ?? "")
                || whatsNew != (original.whatsNew ?? "")
                || marketingUrl != (original.marketingUrl ?? "")
                || supportUrl != (original.supportUrl ?? "")
        }

        func changedAttributes() -> [String: AnyEncodable] {
            var changes: [String: AnyEncodable] = [:]
            if description != (original.description ?? "") { changes["description"] = AnyEncodable(description) }
            if keywords != (original.keywords ?? "") { changes["keywords"] = AnyEncodable(keywords) }
            if promotionalText != (original.promotionalText ?? "") { changes["promotionalText"] = AnyEncodable(promotionalText) }
            if whatsNew != (original.whatsNew ?? "") { changes["whatsNew"] = AnyEncodable(whatsNew) }
            if marketingUrl != (original.marketingUrl ?? "") { changes["marketingUrl"] = AnyEncodable(marketingUrl) }
            if supportUrl != (original.supportUrl ?? "") { changes["supportUrl"] = AnyEncodable(supportUrl) }
            return changes
        }

        mutating func markSaved() {
            original = ASCAppStoreVersionLocalization.Attributes(
                locale: locale,
                description: description,
                keywords: keywords,
                promotionalText: promotionalText,
                whatsNew: whatsNew,
                marketingUrl: marketingUrl,
                supportUrl: supportUrl
            )
        }
    }

    struct AppInfoLocaleDraft: Identifiable {
        let id: String
        let locale: String
        var name: String
        var subtitle: String
        var privacyPolicyUrl: String
        var original: ASCAppInfoLocalization.Attributes

        var isChanged: Bool {
            name != (original.name ?? "")
                || subtitle != (original.subtitle ?? "")
                || privacyPolicyUrl != (original.privacyPolicyUrl ?? "")
        }

        func changedAttributes() -> [String: AnyEncodable] {
            var changes: [String: AnyEncodable] = [:]
            if name != (original.name ?? "") { changes["name"] = AnyEncodable(name) }
            if subtitle != (original.subtitle ?? "") { changes["subtitle"] = AnyEncodable(subtitle) }
            if privacyPolicyUrl != (original.privacyPolicyUrl ?? "") { changes["privacyPolicyUrl"] = AnyEncodable(privacyPolicyUrl) }
            return changes
        }

        mutating func markSaved() {
            original = ASCAppInfoLocalization.Attributes(
                locale: locale,
                name: name,
                subtitle: subtitle,
                privacyPolicyUrl: privacyPolicyUrl,
                privacyPolicyText: original.privacyPolicyText,
                privacyChoicesUrl: original.privacyChoicesUrl
            )
        }
    }

    struct RowPlan: Identifiable {
        let id: UUID
        var rowLabel: String
        var rowSize: CGSize
        var templateCount: Int
        var isEnabled: Bool
        var detectedDisplayType: ASCDisplayType?
        var selectedDisplayType: ASCDisplayType?
        var localeTargets: [LocaleTarget]
    }

    struct LocaleTarget: Identifiable {
        let id = UUID()
        var appLocaleCode: String
        var appLocaleLabel: String
        var selectedASCLocalizationId: String?
        var candidates: [ASCAppStoreVersionLocalization]
        var isEnabled: Bool
    }

    struct UploadPlanEntry: Identifiable {
        let id: String
        let rowLabel: String
        let sourceSizeLabel: String
        let displayTypeLabel: String
        let displayTypeRawValue: String
        let projectLocaleLabel: String
        let projectLocaleCode: String
        let appStoreLocaleCode: String?
        let templateCount: Int
        let isSelected: Bool
        let skipReason: String?

        var screenshotCount: Int { isSelected ? templateCount : 0 }
    }

    struct UploadLocaleGroup: Identifiable {
        let id: String
        let label: String
        let entries: [UploadPlanEntry]

        var screenshotCount: Int { entries.reduce(0) { $0 + $1.screenshotCount } }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 860, height: 680)
        .task { await loadAppsIfNeeded() }
        .sheet(item: $presentedErrorDetails) { details in
            ASCUploadFailureDetailsSheet(details: details.message)
        }
        .confirmationDialog(
            "Replace existing screenshots?",
            isPresented: $isConfirmingUpload,
            titleVisibility: .visible
        ) {
            Button("Upload and Replace", role: .destructive) {
                Task { await startUpload() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationMessage: String {
        let groups = selectedLocaleGroups
        let screenshotCount = groups.reduce(0) { $0 + $1.screenshotCount }
        let localeCount = groups.count
        let setCount = selectedUploadPlanEntries.count
        return "Existing screenshots in each matching display type set will be deleted and replaced. " +
            "\(screenshotCount) screenshot\(screenshotCount == 1 ? "" : "s") will be uploaded across \(setCount) set\(setCount == 1 ? "" : "s") and \(localeCount) locale\(localeCount == 1 ? "" : "s"). " +
            "This cannot be undone."
    }

    // MARK: - Header / footer

    private var header: some View {
        HStack {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            Text("Upload to App Store Connect")
                .font(.headline)
            Spacer()
            if isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 6) {
            backButton
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Details") {
                    presentedErrorDetails = ASCUploadFailureDetailItem(message: errorDetailsText ?? errorMessage)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            Spacer()
            dismissButton
            primaryButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var backButton: some View {
        switch step {
        case .pickingVersion, .editingMetadata, .configuringPlan:
            Button {
                goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(isBusy)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        switch step {
        case .uploading:
            Button("Cancel Upload", role: .cancel) { cancelUpload() }
        case .done:
            Button("Close") { dismiss() }
                .keyboardShortcut(.defaultAction)
        default:
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .pickingApp:
            Button("Next") { Task { await moveToVersion() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedApp == nil || isBusy)
        case .pickingVersion:
            Button("Next") { Task { await moveToMetadata() } }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvanceFromVersion || isBusy)
        case .editingMetadata:
            Button(hasMetadataChanges ? "Save & Continue" : "Continue") {
                Task { await saveMetadataAndContinue() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(isBusy)
        case .configuringPlan:
            Button("Upload") { isConfirmingUpload = true }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStartUpload || isBusy)
        case .uploading, .done:
            EmptyView()
        }
    }

    private var hasMetadataChanges: Bool {
        if copyrightDraft != originalCopyright { return true }
        if versionDrafts.contains(where: \.isChanged) { return true }
        if appInfoDrafts.contains(where: \.isChanged) { return true }
        return false
    }

    private var canAdvanceFromVersion: Bool {
        guard let version = selectedVersion else { return false }
        return version.isEditable
    }

    private func goBack() {
        errorMessage = nil
        errorDetailsText = nil
        switch step {
        case .pickingVersion:
            step = .pickingApp
        case .editingMetadata:
            step = .pickingVersion
        case .configuringPlan:
            step = .editingMetadata
        default: break
        }
    }

    private func cancelUpload() {
        uploadTask?.cancel()
    }

    private var validationIssues: [ASCUploadIssue] {
        guard let version = selectedVersion else { return [] }
        return ASCUploadValidator.validate(version: version, plans: rowPlans)
    }

    private var canStartUpload: Bool {
        !validationIssues.hasErrors
    }

    private var uploadPlanEntries: [UploadPlanEntry] {
        rowPlans.flatMap { plan -> [UploadPlanEntry] in
            guard plan.isEnabled else { return [] }
            let rowLabel = plan.rowLabel.isEmpty ? "Row" : plan.rowLabel
            let sourceSizeLabel = "\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))"
            let displayTypeLabel = plan.selectedDisplayType?.label ?? "No display type selected"
            let displayTypeRawValue = plan.selectedDisplayType?.appStoreConnectValue ?? "none"

            return plan.localeTargets.map { target in
                let appStoreLocale = target.selectedASCLocalizationId.flatMap { selectedId in
                    target.candidates.first(where: { $0.id == selectedId })?.attributes.locale
                }
                let isSelected = target.isEnabled && plan.selectedDisplayType != nil && appStoreLocale != nil
                let skipReason: String?
                if isSelected {
                    skipReason = nil
                } else if target.candidates.isEmpty {
                    skipReason = "No matching App Store locale"
                } else if !target.isEnabled {
                    skipReason = "Unchecked"
                } else if plan.selectedDisplayType == nil {
                    skipReason = "No display type selected"
                } else {
                    skipReason = "No App Store locale selected"
                }

                return UploadPlanEntry(
                    id: "\(plan.id.uuidString)-\(target.id.uuidString)",
                    rowLabel: rowLabel,
                    sourceSizeLabel: sourceSizeLabel,
                    displayTypeLabel: displayTypeLabel,
                    displayTypeRawValue: displayTypeRawValue,
                    projectLocaleLabel: target.appLocaleLabel,
                    projectLocaleCode: target.appLocaleCode,
                    appStoreLocaleCode: appStoreLocale,
                    templateCount: plan.templateCount,
                    isSelected: isSelected,
                    skipReason: skipReason
                )
            }
        }
    }

    private var selectedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter(\.isSelected)
    }

    private var skippedUploadPlanEntries: [UploadPlanEntry] {
        uploadPlanEntries.filter { !$0.isSelected }
    }

    private var selectedLocaleGroups: [UploadLocaleGroup] {
        let grouped = Dictionary(grouping: selectedUploadPlanEntries) { entry in
            entry.appStoreLocaleCode ?? entry.projectLocaleCode
        }
        return grouped.keys.sorted().map { code in
            let entries = grouped[code] ?? []
            let label = entries.first.map { "\($0.projectLocaleLabel) -> \(code)" } ?? code
            return UploadLocaleGroup(id: code, label: label, entries: entries)
        }
    }

    // MARK: - Content by step

    @ViewBuilder
    private var content: some View {
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

    private var missingCredentialsView: some View {
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

    private var pickAppView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select an app")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            List(selection: Binding(
                get: { selectedApp?.id },
                set: { newId in selectedApp = apps.first(where: { $0.id == newId }) }
            )) {
                ForEach(apps) { app in
                    ASCAppHeaderView(app: app, subtitle: app.attributes.bundleId, iconSize: 36)
                        .tag(app.id as String?)
                }
            }
            .listStyle(.inset)
        }
    }

    private var pickVersionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a version")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            if let app = selectedApp {
                ASCAppHeaderView(app: app, subtitle: app.attributes.bundleId)
                    .padding(.horizontal, 16)
            }
            if !versions.isEmpty && !versions.contains(where: { $0.isEditable }) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("No editable version available", systemImage: "lock.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                        .fontWeight(.medium)
                    Text("Every version on this app is locked for review or live. Create a new version in App Store Connect, then refresh this wizard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let app = selectedApp,
                       let url = URL(string: "https://appstoreconnect.apple.com/apps/\(app.id)/appstore") {
                        Link(destination: url) {
                            Label("Open app in App Store Connect", systemImage: "arrow.up.right.square")
                        }
                        .font(.caption)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: .rect(cornerRadius: 8))
                .padding(.horizontal, 16)
            }
            List(selection: Binding(
                get: { selectedVersion?.id },
                set: { newId in selectedVersion = versions.first(where: { $0.id == newId }) }
            )) {
                ForEach(versions) { version in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(version.attributes.versionString)
                                    .fontWeight(.medium)
                                if let platform = version.attributes.displayPlatform {
                                    Text(platform)
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.15), in: .capsule)
                                }
                            }
                            Text(version.attributes.displayState)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !version.isEditable {
                            Label("Read-only", systemImage: "lock.fill")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    .tag(version.id as String?)
                }
            }
            .listStyle(.inset)
            if let version = selectedVersion, !version.isEditable {
                Label("This version is \(version.attributes.displayState) — screenshots can't be changed. Pick an editable version or create a new one in App Store Connect.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
    }

    private var editMetadataView: some View {
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

    private var metadataLocaleSidebar: some View {
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

    private func localeHasChanges(_ code: String) -> Bool {
        if versionDrafts.contains(where: { $0.locale == code && $0.isChanged }) { return true }
        if appInfoDrafts.contains(where: { $0.locale == code && $0.isChanged }) { return true }
        return false
    }

    @ViewBuilder
    private var metadataFormPane: some View {
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

    private var versionCopyrightField: some View {
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
    private func appInfoSection(index: Int) -> some View {
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
    private func versionLocaleSection(index: Int) -> some View {
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

    @ViewBuilder
    private func metadataField(
        label: String,
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
                    .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
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

    private var configurePlanView: some View {
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

    private var uploadSummaryPanel: some View {
        let entries = selectedUploadPlanEntries
        let screenshotCount = entries.reduce(0) { $0 + $1.screenshotCount }
        let issues = validationIssues

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preflight")
                    .font(.subheadline)
                    .fontWeight(.semibold)
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
                                Text("\(entry.projectLocaleLabel) · \(entry.rowLabel): \(entry.skipReason ?? "Skipped")")
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
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: .rect(cornerRadius: 8))
    }

    private func summaryMetric(_ value: String, _ label: String) -> some View {
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

    private func localePlanGroupRow(_ group: UploadLocaleGroup) -> some View {
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

    private var replaceWarningCallout: some View {
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
    private var issuesPanel: some View {
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

    private func calloutBox<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1)
            )
    }

    private func issueRow(_ issue: ASCUploadIssue) -> some View {
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

    private func issueMessageText(_ issue: ASCUploadIssue) -> Text {
        if let scope = issue.scope {
            return Text(scope).fontWeight(.semibold) + Text(" · ") + Text(issue.message)
        }
        return Text(issue.message)
    }

    private func rowPlanCard(plan: Binding<RowPlan>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle(isOn: plan.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.wrappedValue.rowLabel.isEmpty ? "Row" : plan.wrappedValue.rowLabel)
                            .fontWeight(.medium)
                        Text("\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height)) · \(plan.wrappedValue.templateCount) screenshot\(plan.wrappedValue.templateCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                Spacer()
            }

            if plan.wrappedValue.isEnabled {
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

    private func displayTypePicker(plan: Binding<RowPlan>) -> some View {
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
                Text("\(Int(plan.wrappedValue.rowSize.width))×\(Int(plan.wrappedValue.rowSize.height))")
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

    private func displayTypeDetailsPopover(plan: RowPlan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display Type")
                .font(.headline)
            LabeledContent("Source size") {
                Text("\(Int(plan.rowSize.width))×\(Int(plan.rowSize.height))")
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

    private func localeTargetRow(target: Binding<LocaleTarget>) -> some View {
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
    private var uploadProgressView: some View {
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

    private var inProgressView: some View {
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
    private var doneView: some View {
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

    // MARK: - Step transitions

    private func loadAppsIfNeeded() async {
        guard credentials.isConfigured, apps.isEmpty else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            apps = try await AppStoreConnectAPIService.shared.listApps()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if selectedApp == nil,
           let savedId = state.activeProject?.ascAppId,
           let match = apps.first(where: { $0.id == savedId }) {
            selectedApp = match
        }
    }

    private func moveToVersion() async {
        guard let app = selectedApp else { return }
        if let projectId = state.activeProject?.id {
            state.setASCAppId(app.id, forProject: projectId)
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let fetched = try await AppStoreConnectAPIService.shared.listAppStoreVersions(appId: app.id)
            versions = fetched.sorted { lhs, rhs in
                if lhs.isEditable != rhs.isEditable { return lhs.isEditable }
                return lhs.attributes.versionString.compare(
                    rhs.attributes.versionString,
                    options: .numeric
                ) == .orderedDescending
            }
            selectedVersion = versions.first(where: { $0.isEditable }) ?? versions.first
            step = .pickingVersion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveToMetadata() async {
        guard let version = selectedVersion, let app = selectedApp else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            async let localizationsTask = AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            async let appInfosTask = AppStoreConnectAPIService.shared.listAppInfos(appId: app.id)
            let (fetchedLocalizations, fetchedAppInfos) = try await (localizationsTask, appInfosTask)
            localizations = fetchedLocalizations

            let editableInfo = fetchedAppInfos.first(where: { $0.isEditable }) ?? fetchedAppInfos.first
            let fetchedAppInfoLocalizations: [ASCAppInfoLocalization]
            if let editableInfo {
                fetchedAppInfoLocalizations = try await AppStoreConnectAPIService.shared.listAppInfoLocalizations(appInfoId: editableInfo.id)
            } else {
                fetchedAppInfoLocalizations = []
            }

            buildMetadataDrafts(appInfoLocalizations: fetchedAppInfoLocalizations)
            step = .editingMetadata
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildMetadataDrafts(appInfoLocalizations: [ASCAppInfoLocalization]) {
        versionDrafts = localizations
            .sorted { $0.attributes.locale < $1.attributes.locale }
            .map { loc in
                VersionLocaleDraft(
                    id: loc.id,
                    locale: loc.attributes.locale,
                    description: loc.attributes.description ?? "",
                    keywords: loc.attributes.keywords ?? "",
                    promotionalText: loc.attributes.promotionalText ?? "",
                    whatsNew: loc.attributes.whatsNew ?? "",
                    marketingUrl: loc.attributes.marketingUrl ?? "",
                    supportUrl: loc.attributes.supportUrl ?? "",
                    original: loc.attributes
                )
            }
        appInfoDrafts = appInfoLocalizations
            .sorted { $0.attributes.locale < $1.attributes.locale }
            .map { loc in
                AppInfoLocaleDraft(
                    id: loc.id,
                    locale: loc.attributes.locale,
                    name: loc.attributes.name ?? "",
                    subtitle: loc.attributes.subtitle ?? "",
                    privacyPolicyUrl: loc.attributes.privacyPolicyUrl ?? "",
                    original: loc.attributes
                )
            }
        originalCopyright = selectedVersion?.attributes.copyright ?? ""
        copyrightDraft = originalCopyright
        let codes = metadataLocaleCodes
        let currentStillValid = selectedMetadataLocale.map(codes.contains) ?? false
        if !currentStillValid {
            selectedMetadataLocale = codes.first
        }
    }

    private var metadataLocaleCodes: [String] {
        let codes = Set(versionDrafts.map(\.locale)).union(appInfoDrafts.map(\.locale))
        return codes.sorted()
    }

    private func saveMetadataAndContinue() async {
        guard let version = selectedVersion else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let copyrightChanged = copyrightDraft != originalCopyright
        let copyrightValue = copyrightDraft
        let versionSnapshot = versionDrafts
        let appInfoSnapshot = appInfoDrafts
        let api = AppStoreConnectAPIService.shared

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                if copyrightChanged {
                    group.addTask {
                        try await api.updateAppStoreVersion(
                            id: version.id,
                            attributes: ["copyright": AnyEncodable(copyrightValue)]
                        )
                    }
                }
                for draft in versionSnapshot {
                    let changes = draft.changedAttributes()
                    guard !changes.isEmpty else { continue }
                    group.addTask {
                        try await api.updateVersionLocalization(id: draft.id, attributes: changes)
                    }
                }
                for draft in appInfoSnapshot {
                    let changes = draft.changedAttributes()
                    guard !changes.isEmpty else { continue }
                    group.addTask {
                        try await api.updateAppInfoLocalization(id: draft.id, attributes: changes)
                    }
                }
                try await group.waitForAll()
            }
            if copyrightChanged { originalCopyright = copyrightValue }
            for i in versionDrafts.indices where versionDrafts[i].isChanged {
                versionDrafts[i].markSaved()
            }
            for i in appInfoDrafts.indices where appInfoDrafts[i].isChanged {
                appInfoDrafts[i].markSaved()
            }
            rowPlans = buildRowPlans(preserving: rowPlans)
            step = .configuringPlan
        } catch {
            errorMessage = "Failed to save metadata: \(error.localizedDescription)"
        }
    }

    private func refreshLocalizations() async {
        guard let version = selectedVersion else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            localizations = try await AppStoreConnectAPIService.shared.listLocalizations(versionId: version.id)
            rowPlans = buildRowPlans(preserving: rowPlans)
        } catch {
            errorMessage = "Could not refresh locales: \(error.localizedDescription)"
        }
    }

    private func buildRowPlans(preserving existingPlans: [RowPlan] = []) -> [RowPlan] {
        let platform = selectedVersion?.attributes.ascPlatform
        return state.rows.map { row in
            let detected = ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)
            let existingPlan = existingPlans.first(where: { $0.id == row.id })
            let targets = state.localeState.locales.map { locale -> LocaleTarget in
                let matches = ASCLocaleMatcher.matches(appCode: locale.code, in: localizations)
                let existingTarget = existingPlan?.localeTargets.first(where: { $0.appLocaleCode == locale.code })
                let preservedSelection = existingTarget?.selectedASCLocalizationId
                let selectedId: String?
                if let preservedSelection, matches.contains(where: { $0.id == preservedSelection }) {
                    selectedId = preservedSelection
                } else {
                    selectedId = matches.first?.id
                }
                return LocaleTarget(
                    appLocaleCode: locale.code,
                    appLocaleLabel: locale.flagLabel,
                    selectedASCLocalizationId: selectedId,
                    candidates: matches,
                    isEnabled: matches.isEmpty ? false : (existingTarget?.isEnabled ?? true)
                )
            }
            let compatiblePreserved = existingPlan?.selectedDisplayType.flatMap { $0.accepts(platform: platform) ? $0 : nil }
            let detectedCompatible = (detected?.accepts(platform: platform) ?? false) ? detected : nil
            return RowPlan(
                id: row.id,
                rowLabel: row.label,
                rowSize: CGSize(width: row.templateWidth, height: row.templateHeight),
                templateCount: row.templates.count,
                isEnabled: existingPlan?.isEnabled ?? true,
                detectedDisplayType: detected,
                selectedDisplayType: compatiblePreserved ?? detectedCompatible,
                localeTargets: targets
            )
        }
    }

    private func startUpload() async {
        errorMessage = nil
        errorDetailsText = nil
        let issues = validationIssues
        guard !issues.hasErrors else {
            errorMessage = "Fix the preflight errors before uploading."
            return
        }
        let targets = buildUploadTargets()
        guard !targets.isEmpty else {
            errorMessage = "No rows × locales are selected."
            step = .configuringPlan
            return
        }

        step = .uploading
        isBusy = true
        defer { isBusy = false; uploadTask = nil }

        let task = Task {
            do {
                try await AppStoreConnectUploadService.shared.upload(
                    targets: targets,
                    appState: state,
                    progress: { p in self.uploadProgress = p }
                )
                if Task.isCancelled { return }
                let summary = UploadSummary(
                    appId: selectedApp?.id,
                    appName: selectedApp?.attributes.name ?? "",
                    totalScreenshots: targets.reduce(0) { $0 + $1.templateCount * $1.localizations.count },
                    localizationCount: Set(targets.flatMap { $0.localizations.map(\.id) }).count
                )
                uploadSummary = summary
                step = .done
                let shotNoun = summary.totalScreenshots == 1 ? "screenshot" : "screenshots"
                let locNoun = summary.localizationCount == 1 ? "locale" : "locales"
                let body = summary.appName.isEmpty
                    ? "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun)"
                    : "\(summary.totalScreenshots) \(shotNoun) across \(summary.localizationCount) \(locNoun) · \(summary.appName)"
                NotificationService.notify(title: "Upload complete", body: body)
            } catch is CancellationError {
                errorMessage = "Upload cancelled. Any set that was already being replaced may be empty in App Store Connect — re-run the upload to refill it."
                step = .configuringPlan
            } catch {
                let summary = uploadFailureSummary(for: error)
                errorMessage = summary
                errorDetailsText = buildErrorDetails(for: error)
                step = .configuringPlan
                NotificationService.notify(title: "Upload failed", body: summary)
            }
        }
        uploadTask = task
        await task.value
    }

    private func buildUploadTargets() -> [ASCUploadTarget] {
        rowPlans.compactMap { plan -> ASCUploadTarget? in
            guard plan.isEnabled, let displayType = plan.selectedDisplayType else { return nil }
            let localizations = plan.localeTargets.compactMap { target -> ASCUploadLocalization? in
                guard target.isEnabled, let id = target.selectedASCLocalizationId else { return nil }
                return ASCUploadLocalization(id: id, label: target.appLocaleLabel, localeCode: target.appLocaleCode)
            }
            guard !localizations.isEmpty else { return nil }
            return ASCUploadTarget(
                rowId: plan.id,
                rowLabel: plan.rowLabel.isEmpty ? "Row" : plan.rowLabel,
                rowSize: plan.rowSize,
                displayType: displayType,
                localizations: localizations,
                templateCount: plan.templateCount
            )
        }
    }

    private func uploadFailureSummary(for error: Error) -> String {
        if let uploadError = error as? AppStoreConnectUploadError {
            return uploadError.summaryDescription
        }
        return "Upload failed: \(error.localizedDescription)"
    }

    private func buildErrorDetails(for error: Error) -> String {
        var details: [String] = [error.localizedDescription]
        if let app = selectedApp {
            details.append("App: \(app.attributes.name) (\(app.attributes.bundleId))")
        }
        if let version = selectedVersion {
            let platform = version.attributes.displayPlatform.map { " \($0)" } ?? ""
            details.append("Version: \(version.attributes.versionString)\(platform) · \(version.attributes.displayState)")
        }
        if let uploadError = error as? AppStoreConnectUploadError {
            details.append("Technical details:\n\(uploadError.technicalDescription)")
        }
        return details.joined(separator: "\n\n")
    }
}
