import SwiftUI
import UniformTypeIdentifiers

// Settings UI lives in a plain Window scene (the Settings scene is non-resizable on
// macOS 26); an iPad settings surface is a follow-up.
#if os(macOS)
struct SettingsView: View {
    static let windowID = "settings"

    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var appState
    @Environment(MCPServerService.self) private var mcpServer
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("appLanguageOverride") private var languageOverride = ""
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportCustomSuffix") private var exportCustomSuffix = ""
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("lastExportFolderBookmark") private var lastExportFolderBookmark = Data()
    @AppStorage("lastExportFolderPath") private var lastExportFolderPath = ""
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""
    @AppStorage("projectSortOrder") private var projectSortOrder = "creation"

    @State private var selection: SettingsSection? = .general
    @State private var showLanguageRelaunchAlert = false

    @State private var iCloudEnabled = ICloudSyncService.shared.isEnabled
    @State private var iCloudAvailable = ICloudSyncService.shared.isAvailable
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false
    @State private var iCloudMigrationProgress: Double?
    @State private var iCloudError: String?

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

            languagePicker

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
                if !iCloudAvailable {
                    Label("iCloud is not available. Sign in to iCloud in System Settings.",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Sync with iCloud", isOn: Binding(
                        get: { iCloudEnabled },
                        set: { newValue in
                            if newValue {
                                showEnableConfirmation = true
                            } else {
                                showDisableConfirmation = true
                            }
                        }
                    ))
                    .disabled(iCloudMigrationProgress != nil)

                    if let progress = iCloudMigrationProgress {
                        HStack(spacing: 8) {
                            ProgressView(value: progress)
                            Text("\(Int(progress * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }

                    if iCloudEnabled {
                        // Plain HStack rather than LabeledContent: LabeledContent gives its trailing
                        // content a flexible frame, which made this (conditional Label) row balloon
                        // to a huge height.
                        HStack {
                            Text("Status")
                            Spacer()
                            iCloudStatusLabel
                        }
                    }

                    if let error = iCloudError {
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
                Button("Enable iCloud Sync") { toggleICloud(enable: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All projects will be copied to iCloud. Initial sync may take time for large projects.")
            }
            .confirmationDialog(
                "Disable iCloud Sync",
                isPresented: $showDisableConfirmation,
                titleVisibility: .visible
            ) {
                Button("Disable iCloud Sync", role: .destructive) { toggleICloud(enable: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Projects will be kept locally. Other Macs will no longer see updates.")
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
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var iCloudStatusLabel: some View {
        let monitor = ICloudSyncService.shared
        if monitor.isUsingICloud {
            Label("Syncing via iCloud", systemImage: "checkmark.icloud")
                .foregroundStyle(.green)
        } else {
            Label("Connecting...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var languagePicker: some View {
        Picker("Language", selection: $languageOverride) {
            Text("System").tag("")
            ForEach(AppLanguageOptions.available, id: \.self) { code in
                Text(AppLanguageOptions.displayName(for: code)).tag(code)
            }
        }
        .onChange(of: languageOverride) { _, newValue in
            AppLanguageOptions.apply(newValue)
            showLanguageRelaunchAlert = true
        }
        .alert("Restart to change language", isPresented: $showLanguageRelaunchAlert) {
            Button("Restart Now") { relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The interface language will switch the next time Screenshot Bro launches.")
        }
    }

    private func relaunchApp() {
        guard let url = Bundle.main.bundleURL as URL? else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    private func toggleICloud(enable: Bool) {
        let sync = ICloudSyncService.shared
        iCloudMigrationProgress = 0
        iCloudError = nil

        Task {
            do {
                let operation = enable ? sync.enable : sync.disable
                try await operation { progress in
                    Task { @MainActor in
                        iCloudMigrationProgress = progress
                    }
                }
                iCloudEnabled = enable
                iCloudMigrationProgress = nil
            } catch {
                iCloudError = error.localizedDescription
                iCloudMigrationProgress = nil
            }
        }
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
                            guard let url = ExportFolderService.chooseFolder(),
                                  let result = ExportFolderService.saveBookmark(for: url) else { return }
                            lastExportFolderBookmark = result.bookmark
                            lastExportFolderPath = result.path
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
                let suffixPart = ExportService.formattedFileSuffix(exportCustomSuffix)
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
                lastExportFolderBookmark = Data()
                lastExportFolderPath = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Clear export folder")
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
                    planDetailRows(for: tier)
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
                    proFeatureRow("Unlimited projects")
                    proFeatureRow("Unlimited rows per project")
                    proFeatureRow("Unlimited screenshots per row")
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
                freeTierSections
            }

            Section("Legal") {
                Link("Terms of Use", destination: AppLinks.terms)
                Link("Privacy Policy", destination: AppLinks.privacy)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func planDetailRows(for tier: StoreService.ProTier) -> some View {
        switch tier {
        case .lifetime:
            LabeledContent("Purchase type") {
                Text("One-time purchase")
                    .foregroundStyle(.secondary)
            }
        case .subscription(_, let expirationDate, let willRenew):
            LabeledContent(willRenew ? "Renews" : "Expires") {
                Text(expirationDate, format: .dateTime.year().month().day())
                    .foregroundStyle(.secondary)
            }
            Link("Manage Subscription", destination: StoreService.manageSubscriptionsURL)
        }
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

    @ViewBuilder
    private var freeTierSections: some View {
        Section("Compare Plans") {
            comparisonRow(
                title: "Projects",
                freeValue: "1",
                proValue: String(localized: "Unlimited")
            )
            comparisonRow(
                title: "Rows per project",
                freeValue: "\(StoreService.freeMaxRows)",
                proValue: String(localized: "Unlimited")
            )
            comparisonRow(
                title: "Screenshots per row",
                freeValue: "\(StoreService.freeMaxTemplatesPerRow)",
                proValue: String(localized: "Unlimited")
            )
        }

        Section("Upgrade") {
            Button("Unlock Screenshot Bro Pro") {
                store.presentPaywall(for: .general)
            }
            .buttonStyle(.borderedProminent)

            Button("Restore Purchase") {
                Task { await store.restore() }
            }
            .buttonStyle(.bordered)
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

    private func proFeatureRow(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark")
            .foregroundStyle(.primary)
    }

    @MainActor
    private func createBackup() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "screenshot-backup-\(formatter.string(from: Date())).zip"
        panel.allowedContentTypes = [.zip]
        guard panel.runModal() == .OK, let destURL = panel.url else { return }

        isBackingUp = true
        backupResult = nil

        let sourceURL = PersistenceService.rootURL
        Task {
            do {
                let tempZip = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + ".zip")
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
                process.arguments = ["-r", tempZip.path, "."]
                process.currentDirectoryURL = sourceURL
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    process.terminationHandler = { _ in continuation.resume() }
                    do {
                        try process.run()
                    } catch {
                        process.terminationHandler = nil
                        continuation.resume(throwing: error)
                    }
                }
                guard process.terminationStatus == 0 else {
                    try? FileManager.default.removeItem(at: tempZip)
                    isBackingUp = false
                    backupResult = .failure(String(localized: "Backup failed (zip exited with status \(process.terminationStatus))."))
                    return
                }
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.moveItem(at: tempZip, to: destURL)
                isBackingUp = false
                backupResult = BackupResult.success
            } catch {
                isBackingUp = false
                backupResult = .failure(error.localizedDescription)
            }
        }
    }

    private func comparisonRow(title: LocalizedStringKey, freeValue: String, proValue: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer()
            Text("Free: \(freeValue)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("Pro: \(proValue)")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}

#Preview {
    SettingsView()
        .environment(StoreService())
        .environment(AppState())
        .environment(MCPServerService())
}
#endif
