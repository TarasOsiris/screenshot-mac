import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    private static let privacyPolicyURL = URL(string: "https://screenshotbro.app/privacy")!
    private static let termsURL = URL(string: "https://screenshotbro.app/terms")!

    @Environment(StoreService.self) private var store
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("appLanguageOverride") private var languageOverride = ""
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("lastExportFolderBookmark") private var lastExportFolderBookmark = Data()
    @AppStorage("lastExportFolderPath") private var lastExportFolderPath = ""
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""
    @AppStorage("projectSortOrder") private var projectSortOrder = "creation"

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

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                generalSettings
            }

            Tab("Export", systemImage: "square.and.arrow.up") {
                exportSettings
            }

            Tab("App Store Connect", systemImage: "arrow.up.circle") {
                AppStoreConnectSettingsView()
            }

            Tab("Purchase", systemImage: "star") {
                purchaseSettings
            }

            Tab("Attributions", systemImage: "heart") {
                attributionsSettings
            }
        }
        .frame(width: 520, height: 560)
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
                        LabeledContent("Status") {
                            iCloudStatusLabel
                        }
                    }

                    if let error = iCloudError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
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
            ForEach(Self.availableAppLanguages, id: \.self) { code in
                Text(Self.displayName(forLanguageCode: code)).tag(code)
            }
        }
        .onChange(of: languageOverride) { _, newValue in
            applyLanguageOverride(newValue)
            showLanguageRelaunchAlert = true
        }
        .alert("Restart to change language", isPresented: $showLanguageRelaunchAlert) {
            Button("Restart Now") { relaunchApp() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("The interface language will switch the next time Screenshot Bro launches.")
        }
    }

    private static var availableAppLanguages: [String] {
        Bundle.main.localizations
            .filter { $0 != "Base" }
            .sorted()
    }

    private static func displayName(forLanguageCode code: String) -> String {
        let localeInOwnLanguage = Locale(identifier: code)
        if let name = localeInOwnLanguage.localizedString(forLanguageCode: code) {
            return name.capitalized(with: localeInOwnLanguage)
        }
        return code
    }

    private func applyLanguageOverride(_ code: String) {
        if code.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
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

    private var purchaseSettings: some View {
        Form {
            Section {
                LabeledContent("Plan") {
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
                Link("Terms of Use", destination: Self.termsURL)
                Link("Privacy Policy", destination: Self.privacyPolicyURL)
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
            Section("3D Models") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("iPhone 17 Pro")
                        .fontWeight(.medium)
                    Text("by Ibrahim.Bhl")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("License: CC Attribution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Link("View on Sketchfab",
                         destination: URL(string: "https://sketchfab.com/3d-models/iphone-17-pro-4aeeeb41f9d14f96bb3f2589edc3edac")!)
                        .font(.caption)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text("iPhone 17 Pro Max")
                        .fontWeight(.medium)
                    Text("by izatrcsldssb")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text("License: CC Attribution")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Link("View on Sketchfab",
                         destination: URL(string: "https://sketchfab.com/3d-models/iphone-17-pro-max-d24511d4d7534a4b89efdcf8fb6fae88")!)
                        .font(.caption)
                }
                .padding(.vertical, 2)
            }

            Section("Templates") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("500 App Store Screenshot Templates")
                        .fontWeight(.medium)
                    Text("for Android and iOS Apps")
                        .foregroundStyle(.secondary)
                    Link("View on Figma Community",
                         destination: URL(string: "https://www.figma.com/community/file/1471925742378558731/500-app-store-screenshot-templates-for-android-and-ios-apps")!)
                        .font(.caption)
                }
                .padding(.vertical, 2)
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
}
