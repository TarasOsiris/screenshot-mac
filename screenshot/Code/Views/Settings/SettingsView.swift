import SwiftUI
import UniformTypeIdentifiers

// Settings UI lives in a plain Window scene (the Settings scene is non-resizable on
// macOS 26); an iPad settings surface is a follow-up.
#if os(macOS)
// Lets callers request a specific tab when opening the settings window (e.g. the
// missing-API-key prompts). The plain Window scene can't carry a value, so this
// singleton bridges the request to the already-mounted SettingsView.
@MainActor
@Observable
final class SettingsWindowNavigation {
    static let shared = SettingsWindowNavigation()
    var requestedSection: SettingsView.SettingsSection?
    private init() {}
}

struct SettingsView: View {
    static let windowID = "settings"

    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(ICloudSyncStatusModel.self) private var iCloudStatus
    @Environment(MCPServerService.self) private var mcpServer
    @AppStorage(AppSettingsKeys.appearance) private var appearance = AppSettingsKeys.Default.appearance
    @AppStorage(AppSettingsKeys.appLanguageOverride) private var languageOverride = ""
    @AppStorage(AppSettingsKeys.defaultScreenshotSize) private var defaultScreenshotSize = AppSettingsKeys.Default.defaultScreenshotSize
    @AppStorage(AppSettingsKeys.exportFormat) private var exportFormat = AppSettingsKeys.Default.exportFormat
    @AppStorage(AppSettingsKeys.exportCustomSuffix) private var exportCustomSuffix = ""
    @AppStorage(AppSettingsKeys.openExportFolderOnSuccess) private var openExportFolderOnSuccess = AppSettingsKeys.Default.openExportFolderOnSuccess
    /// Observation only — `ExportFolderBookmark` owns every read and write of the bookmark pair.
    @AppStorage(ExportFolderBookmark.pathKey) private var lastExportFolderPath = ""
    @AppStorage(AppSettingsKeys.defaultTemplateCount) private var defaultTemplateCount = AppSettingsKeys.Default.defaultTemplateCount
    @AppStorage(AppSettingsKeys.defaultZoomLevel) private var defaultZoomLevel = AppSettingsKeys.Default.defaultZoomLevel
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) private var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @AppStorage(AppSettingsKeys.defaultDeviceCategory) private var defaultDeviceCategoryRaw = AppSettingsKeys.Default.defaultDeviceCategory
    @AppStorage(AppSettingsKeys.defaultDeviceFrameId) private var defaultDeviceFrameId = ""
    @AppStorage(AppSettingsKeys.projectSortOrder) private var projectSortOrder = AppSettingsKeys.Default.projectSortOrder

    @State private var selection: SettingsSection? = .general
    @State private var copiedDiagnostics = false
    @State private var iCloud = ICloudSettingsModel()
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false

    @State private var isBackingUp = false
    @State private var backupResult: BackupResult?

    enum BackupResult { case success; case failure(String) }

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, export, appStoreConnect, googlePlay, automation, purchase, attributions

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .export: "Export"
            case .appStoreConnect: "App Store Connect"
            case .googlePlay: "Google Play"
            case .automation: "Automation"
            case .purchase: "Purchase"
            case .attributions: "Attributions"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .export: "square.and.arrow.up"
            case .appStoreConnect: "arrow.up.circle"
            case .googlePlay: "play.rectangle.on.rectangle"
            case .automation: "terminal"
            case .purchase: "star"
            case .attributions: "heart"
            }
        }

        /// The Help topic that documents this pane, so the pane doesn't have to restate it.
        var helpTopic: HelpSection? {
            switch self {
            case .general: .settings
            case .export: .exporting
            case .appStoreConnect: .appStoreConnect
            case .googlePlay: .googlePlay
            case .automation: .automation
            case .purchase: .proFeatures
            case .attributions: nil
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(UIMetrics.Window.settingsSidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContent
                .navigationTitle((selection ?? .general).title)
                .toolbar {
                    if let topic = (selection ?? .general).helpTopic {
                        ToolbarItem(placement: .primaryAction) {
                            HelpTopicButton(section: topic)
                        }
                    }
                }
        }
        .frame(
            minWidth: UIMetrics.Window.settingsMinSize.width,
            idealWidth: UIMetrics.Window.settings.width,
            maxWidth: .infinity,
            minHeight: UIMetrics.Window.settingsMinSize.height,
            idealHeight: UIMetrics.Window.settings.height,
            maxHeight: .infinity
        )
        .background(WindowSceneBridge(role: .settings))
        .screenView(.settings)
        .onAppear(perform: applyRequestedSection)
        .onChange(of: SettingsWindowNavigation.shared.requestedSection) { _, _ in
            applyRequestedSection()
        }
    }

    private func applyRequestedSection() {
        guard let requested = SettingsWindowNavigation.shared.requestedSection else { return }
        selection = requested
        SettingsWindowNavigation.shared.requestedSection = nil
    }

    // Keep every pane mounted and toggle visibility rather than switching (which would rebuild the
    // selected pane on each navigation, discarding transient @State like a shown "Connection
    // succeeded" result or an in-flight test spinner in the App Store Connect / Google Play panes).
    private var detailContent: some View {
        let active = selection ?? .general
        return ZStack {
            ForEach(SettingsSection.allCases) { section in
                detailView(for: section)
                    .opacity(section == active ? 1 : 0)
                    .allowsHitTesting(section == active)
                    .accessibilityHidden(section != active)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general: generalSettings
        case .export: exportSettings
        case .appStoreConnect: AppStoreConnectSettingsView()
        case .googlePlay: GooglePlaySettingsView()
        case .automation: automationSettings
        case .purchase: purchaseSettings
        case .attributions: attributionsSettings
        }
    }

    private var generalSettings: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }

            AppLanguagePicker(languageOverride: $languageOverride)

            ScreenshotSizePicker(selection: $defaultScreenshotSize)

            DefaultDevicePicker(categoryRaw: $defaultDeviceCategoryRaw, frameId: $defaultDeviceFrameId)

            TemplateCountPicker(selection: $defaultTemplateCount)

            Toggle("Ask before deleting rows and screenshots", isOn: $confirmBeforeDeleting)

            Picker("Project order", selection: $projectSortOrder) {
                Text("By creation date").tag("creation")
                Text("Alphabetically").tag("alphabetical")
            }

            Picker("Default zoom level", selection: $defaultZoomLevel) {
                ForEach(ZoomConstants.presets, id: \.self) { preset in
                    Text("\(Int(preset * 100))%").tag(Double(preset))
                }
            }
            Section("iCloud Sync") {
                if !iCloud.isAvailable {
                    Label("iCloud is not available. Sign in to iCloud in System Settings.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { iCloud.isEnabled },
                        set: { newValue in
                            if newValue {
                                showEnableConfirmation = true
                            } else {
                                showDisableConfirmation = true
                            }
                        }
                    ))
                    .disabled(iCloud.isMigrating)

                    if let progress = iCloud.migrationProgress {
                        HStack(spacing: 8) {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if iCloud.isEnabled {
                        // Plain HStack rather than LabeledContent: LabeledContent gives its trailing
                        // content a flexible frame, which made this (conditional Label) row balloon
                        // to a huge height.
                        HStack {
                            Text("Status")
                            Spacer()
                            ICloudStatusLabel(syncStatus: iCloudStatus.status)
                        }
                    }

                    if let error = iCloud.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }

                    Text("Syncing may take a while if you have a lot of projects.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .confirmationDialog(
                "Enable iCloud Sync",
                isPresented: $showEnableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Enable iCloud Sync") { iCloud.toggle(enable: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All projects will be copied to iCloud. Initial sync may take time for large projects.")
            }
            .confirmationDialog(
                "Disable iCloud Sync",
                isPresented: $showDisableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disable iCloud Sync", role: .destructive) { iCloud.toggle(enable: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Projects will be kept locally. Other Macs will no longer see updates.")
            }

            Section("Help") {
                LabeledContent("Editor tour") {
                    Button("Replay Tour") {
                        // Not persisted: the first-run flag is already spent, and counting a
                        // deliberate replay would inflate the onboarding funnel.
                        appState.coach.start(persistOnEnd: false)
                        AppWindowManager.shared.showMainWindow()
                    }
                    .disabled(appState.activeProjectId == nil || !OnboardingCoachStep.tourSupportedOnDevice)
                }
                if appState.activeProjectId == nil {
                    Text("Open a project to replay the tour — its steps point at the editor.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Storage") {
                LabeledContent("Project storage") {
                    Button("Open in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([PersistenceService.rootURL])
                    }
                }
                LabeledContent("Backup") {
                    HStack(spacing: 8) {
                        if isBackingUp {
                            ProgressView().controlSize(.small)
                        }
                        Button("Create Backup…") { createBackup() }
                            .disabled(isBackingUp)
                    }
                }
                if let result = backupResult {
                    switch result {
                    case .success:
                        Text("Backup saved successfully.")
                            .font(.caption).foregroundStyle(.green)
                    case .failure(let message):
                        Text(message)
                            .font(.caption).foregroundStyle(.red)
                    }
                }
            }

            Section {
                LabeledContent("Version") {
                    Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Diagnostics") {
                    Button(copiedDiagnostics ? "Copied" : "Copy Diagnostics") {
                        PlatformPasteboard.copyString(
                            DiagnosticsSnapshot.text(state: appState, store: store)
                        )
                        copiedDiagnostics = true
                    }
                }
            } footer: {
                Text("Paste this into a support email so we can match your report to the crash reports we received. It contains version and setup details only — no project content.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var exportSettings: some View {
        Form {
            Section {
                LabeledContent("Export folder") {
                    HStack(spacing: 6) {
                        if !lastExportFolderPath.isEmpty {
                            pathPillView
                        } else {
                            Text("Ask each time")
                                .foregroundStyle(.tertiary)
                        }
                        Button("Choose…") {
                            guard let url = ExportFolderService.chooseFolder() else { return }
                            ExportFolderBookmark().save(url)
                        }
                    }
                }
            } footer: {
                Text("When set, Cmd+E exports directly to this folder without prompting.")
                    .foregroundStyle(.secondary)
            }

            Picker("Format", selection: $exportFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }

            Section {
                TextField("Custom filename suffix", text: $exportCustomSuffix, prompt: Text("optional"))
            } footer: {
                let suffixPart = ExportFileNaming.formattedFileSuffix(exportCustomSuffix)
                let ext = (ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png).fileExtension
                Text("Example: 01_Onboarding_en\(suffixPart).\(ext)")
                    .foregroundStyle(.secondary)
            }

            Toggle("Reveal in Finder after export", isOn: $openExportFolderOnSuccess)
        }
        .formStyle(.grouped)
    }

    private var pathPillView: some View {
        HStack(spacing: 4) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .font(.caption)
            Text(ExportFolderService.folderName(for: lastExportFolderPath))
                .lineLimit(1)
                .truncationMode(.middle)
            Button {
                ExportFolderBookmark().clear()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Clear export folder")
            .accessibilityLabel("Clear export folder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: .capsule)
        .help(lastExportFolderPath)
    }

    private var automationSettings: some View {
        Form {
            Section {
                if mcpServer.isTransitioning {
                    LabeledContent("Enable MCP server") {
                        HStack(spacing: 8) {
                            Text(mcpTransitionLabel)
                                .foregroundStyle(.secondary)
                            ProgressView().controlSize(.small)
                        }
                    }
                } else {
                    Toggle("Enable MCP server", isOn: Binding(
                        get: { mcpServer.isEnabled },
                        set: { mcpServer.setEnabled($0, state: appState) }
                    ))
                }
            } footer: {
                Text("Runs a local server on 127.0.0.1 so AI agents and MCP clients (like Claude Code) can create and edit projects, translate text, and export screenshots on your behalf.")
                    .foregroundStyle(.secondary)
            }

            if mcpServer.isEnabled && !mcpServer.isTransitioning {
                Section("Status") {
                    mcpStatusRow
                }

                Section {
                    LabeledContent("Server URL") {
                        copyableValue(mcpServer.serverURL, monospaced: true, tooltip: "Copy server URL")
                    }
                    if let token = mcpServer.authToken {
                        LabeledContent("Access Token") {
                            copyableValue(token, masked: true, tooltip: "Copy access token")
                        }
                    }
                    Button {
                        copyToPasteboard(mcpServer.agentPrompt)
                    } label: {
                        Label("Copy Agent Prompt", systemImage: "sparkles")
                    }
                    Button("Copy Configuration (JSON)") {
                        copyToPasteboard(mcpServer.configurationJSON)
                    }
                    if mcpServer.authToken != nil {
                        Button("Regenerate Access Token") {
                            mcpServer.regenerateToken(state: appState)
                        }
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    if mcpServer.authToken != nil {
                        Text("Easiest: paste the agent prompt into your AI assistant and let it connect. Or add the server by hand with the URL and access token, or the JSON configuration. Keep the token private — anyone with it can control the app while the server is running.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Easiest: paste the agent prompt into your AI assistant and let it connect. Or add the server by hand with the URL or the JSON configuration, then restart the client.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var mcpStatusRow: some View {
        switch mcpServer.status {
        case .stopped:
            Label("Not running", systemImage: "circle")
                .foregroundStyle(.secondary)
        case .starting:
            Label("Starting…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .running(let port):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Running")
                Spacer()
                Text(verbatim: "127.0.0.1:\(port)")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }

    private var mcpTransitionLabel: LocalizedStringKey {
        switch mcpServer.transition {
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .restarting: "Restarting…"
        case nil: "Working…"
        }
    }

    private func copyableValue(_ value: String, monospaced: Bool = false, masked: Bool = false, tooltip: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Text(verbatim: masked ? "••••••••••••" : value)
                .font(monospaced ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
            ActionButton(icon: "doc.on.doc", tooltip: tooltip) {
                copyToPasteboard(value)
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var purchaseSettings: some View {
        Form {
            Section {
                // Plain HStack rather than LabeledContent: LabeledContent gives its trailing
                // content a flexible frame, which made this (conditional Label) row balloon
                // to a huge height.
                HStack {
                    Text("Plan")
                    Spacer()
                    if store.isProUnlocked {
                        Label(store.proTier?.displayName ?? String(localized: "Pro"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Free")
                            .foregroundStyle(.secondary)
                    }
                }

                if let tier = store.proTier {
                    PlanDetailRows(tier: tier)
                }

                if let appUserID = store.appUserID {
                    LabeledContent("RevenueCat ID") {
                        HStack(spacing: 6) {
                            Text(appUserID)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            ActionButton(icon: "doc.on.doc", tooltip: "Copy RevenueCat ID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(appUserID, forType: .string)
                            }
                        }
                    }
                }
            }

            purchaseStatusSection

            if store.isProUnlocked {
                Section("Included") {
                    ProFeatureRow(text: "Unlimited projects")
                    ProFeatureRow(text: "Unlimited rows per project")
                    ProFeatureRow(text: "Unlimited screenshots per row")
                }

                Section("Purchase Status") {
                    Label("Screenshot Bro Pro is unlocked.", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                    Text("Your unlock is managed by the App Store for this Apple Account.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                FreeTierSections(store: store)
            }

            Section("Legal") {
                Link("Terms of Use", destination: AppLinks.terms)
                Link("Privacy Policy", destination: AppLinks.privacy)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var purchaseStatusSection: some View {
        if let configurationIssue = store.configurationIssue {
            Section("RevenueCat") {
                Label(configurationIssue, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }

        if let purchaseStatusMessage = store.purchaseStatusMessage {
            Section("Status") {
                Label(
                    purchaseStatusMessage,
                    systemImage: store.purchaseStatusIsError
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(store.purchaseStatusIsError ? .red : .secondary)
            }
        }
    }

    private var attributionsSettings: some View {
        Form {
            ForEach(AppAttribution.Category.allCases) { category in
                Section(category.title) {
                    ForEach(AppAttribution.inCategory(category)) { credit in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(credit.title)
                                .fontWeight(.medium)
                            Text(credit.subtitle)
                                .foregroundStyle(.secondary)
                            if let license = credit.license {
                                Text(license)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Link(credit.linkTitle, destination: credit.url)
                                .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @MainActor
    private func createBackup() {
        guard let destURL = BackupService.chooseDestination() else { return }

        isBackingUp = true
        backupResult = nil
        Task {
            do {
                try await BackupService.createBackup(to: destURL)
                backupResult = BackupResult.success
            } catch {
                backupResult = .failure(error.localizedDescription)
            }
            isBackingUp = false
        }
    }

}

#Preview {
    let state = AppState()
    SettingsView()
        .environment(StoreService())
        .environment(state)
        .environment(state.iCloudStatus)
        .environment(MCPServerService())
}
#endif
