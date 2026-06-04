#if os(iOS)
import SwiftUI

/// iPad Settings surface — the relevant subset of the macOS Settings scene, presented as a
/// grouped Form inside the Settings tab. macOS-only features (Finder reveal, zip backup,
/// export-folder bookmark, App Store Connect upload) are omitted.
struct IPadSettingsView: View {
    @Environment(StoreService.self) private var store
    @Environment(AppState.self) private var state
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("appLanguageOverride") private var languageOverride = ""
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("exportCustomSuffix") private var exportCustomSuffix = ""
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""
    @AppStorage("projectSortOrder") private var projectSortOrder = "creation"

    @State private var showLanguageRestartAlert = false

    @State private var iCloudEnabled = ICloudSyncService.shared.isEnabled
    @State private var iCloudAvailable = ICloudSyncService.shared.isAvailable
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false
    @State private var iCloudMigrationProgress: Double?
    @State private var iCloudError: String?

    var body: some View {
        Form {
            if !store.isProUnlocked {
                proUpsellSection
            }
            appearanceSection
            defaultsSection
            editingSection
            exportSection
            iCloudSection
            purchaseSection
            legalSection
            attributionsSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        // The Settings tab is long-lived inside the TabView, and ICloudSyncService isn't
        // @Observable — so re-read its state whenever the tab reappears or sync flips.
        .onAppear(perform: refreshICloudState)
        .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncDidEnable)) { _ in refreshICloudState() }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncDidDisable)) { _ in refreshICloudState() }
        // Attached to the Form (not the iCloud Section): presentation modifiers on a Section
        // inside a Form render a phantom full-height empty block.
        .alert("Enable iCloud Sync", isPresented: $showEnableConfirmation) {
            Button("Enable iCloud Sync") { toggleICloud(enable: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All projects will be copied to iCloud. Initial sync may take time for large projects.")
        }
        .confirmationDialog("Disable iCloud Sync", isPresented: $showDisableConfirmation, titleVisibility: .visible) {
            Button("Disable iCloud Sync", role: .destructive) { toggleICloud(enable: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Projects will be kept locally. Other devices will no longer see updates.")
        }
    }

    private func refreshICloudState() {
        iCloudAvailable = ICloudSyncService.shared.isAvailable
        iCloudEnabled = ICloudSyncService.shared.isEnabled
    }

    // MARK: - Pro upsell

    /// Large, prominent unlock-Pro call to action at the very top of Settings (free tier only).
    private var proUpsellSection: some View {
        Section {
            Button {
                store.presentPaywall(for: .general)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlock Screenshot Bro Pro")
                            .font(.headline)
                        Text("Unlimited projects, rows, and screenshots")
                            .font(.subheadline)
                            .opacity(0.85)
                    }
                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Appearance", selection: $appearance) {
                Text("Auto").tag("auto")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            languagePicker
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
            showLanguageRestartAlert = true
        }
        .alert("Restart to change language", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Quit and reopen Screenshot Bro to switch the interface language.")
        }
    }

    // MARK: - Defaults

    private var defaultsSection: some View {
        Section("New Project Defaults") {
            ScreenshotSizePicker(selection: $defaultScreenshotSize)
            DefaultDevicePicker(categoryRaw: $defaultDeviceCategoryRaw, frameId: $defaultDeviceFrameId)
            TemplateCountPicker(selection: $defaultTemplateCount)
            Picker("Default zoom level", selection: $defaultZoomLevel) {
                ForEach(ZoomConstants.presets, id: \.self) { preset in
                    Text("\(Int(preset * 100))%").tag(Double(preset))
                }
            }
        }
    }

    // MARK: - Editing

    private var editingSection: some View {
        Section("Editing") {
            Toggle("Ask before deleting rows and screenshots", isOn: $confirmBeforeDeleting)
            Picker("Project order", selection: $projectSortOrder) {
                Text("By creation date").tag("creation")
                Text("Alphabetically").tag("alphabetical")
            }
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Picker("Format", selection: $exportFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }
            TextField("Custom filename suffix", text: $exportCustomSuffix, prompt: Text("optional"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            Text("Export")
        } footer: {
            let suffixPart = ExportService.formattedFileSuffix(exportCustomSuffix)
            let ext = (ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png).fileExtension
            Text("Example: 01_Onboarding_en\(suffixPart).\(ext)")
        }
    }

    // MARK: - iCloud

    @ViewBuilder
    private var iCloudSection: some View {
        Section("iCloud Sync") {
            if !iCloudAvailable {
                Label("iCloud is not available. Sign in to iCloud in Settings.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Sync with iCloud", isOn: Binding(
                    get: { iCloudEnabled },
                    set: { newValue in
                        if newValue { showEnableConfirmation = true } else { showDisableConfirmation = true }
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
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var iCloudStatusLabel: some View {
        if !ICloudSyncService.shared.isUsingICloud {
            Label("Connecting...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else {
            switch state.iCloudSyncStatus {
            case .downloading(let p):
                Label("Downloading \(Int(p * 100))%", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            case .uploading(let p):
                Label("Uploading \(Int(p * 100))%", systemImage: "arrow.up.circle")
                    .foregroundStyle(.secondary)
            case .idle:
                Label("Syncing via iCloud", systemImage: "checkmark.icloud")
                    .foregroundStyle(.green)
            }
        }
    }

    // MARK: - Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        Section("Purchase") {
            LabeledContent("Plan") {
                if store.isProUnlocked {
                    Label(store.proTier?.displayName ?? String(localized: "Pro"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Text("Free").foregroundStyle(.secondary)
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
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        ActionButton(icon: "doc.on.doc", tooltip: "Copy RevenueCat ID") {
                            PlatformPasteboard.copyString(appUserID)
                        }
                    }
                }
            }
        }

        if store.isProUnlocked {
            Section("Included") {
                proFeatureRow("Unlimited projects")
                proFeatureRow("Unlimited rows per project")
                proFeatureRow("Unlimited screenshots per row")
            }
        } else {
            freeTierSections
        }
    }

    @ViewBuilder
    private func planDetailRows(for tier: StoreService.ProTier) -> some View {
        switch tier {
        case .lifetime:
            LabeledContent("Purchase type") {
                Text("One-time purchase").foregroundStyle(.secondary)
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
    private var freeTierSections: some View {
        Section("Compare Plans") {
            comparisonRow(title: "Projects", freeValue: "1", proValue: String(localized: "Unlimited"))
            comparisonRow(title: "Rows per project", freeValue: "\(StoreService.freeMaxRows)", proValue: String(localized: "Unlimited"))
            comparisonRow(title: "Screenshots per row", freeValue: "\(StoreService.freeMaxTemplatesPerRow)", proValue: String(localized: "Unlimited"))
        }

        Section("Upgrade") {
            Button("Unlock Screenshot Bro Pro") {
                store.presentPaywall(for: .general)
            }
            Button("Restore Purchase") {
                Task { await store.restore() }
            }
        }
    }

    private func proFeatureRow(_ text: LocalizedStringKey) -> some View {
        Label(text, systemImage: "checkmark")
    }

    private func comparisonRow(title: LocalizedStringKey, freeValue: String, proValue: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer()
            Text("Free: \(freeValue)").foregroundStyle(.secondary).monospacedDigit()
            Text("Pro: \(proValue)").fontWeight(.semibold).monospacedDigit()
        }
    }

    // MARK: - Legal & Attributions

    private var legalSection: some View {
        Section("Legal") {
            Link("Terms of Use", destination: AppLinks.terms)
            Link("Privacy Policy", destination: AppLinks.privacy)
        }
    }

    private var attributionsSection: some View {
        Section("Attributions") {
            ForEach(AppAttribution.all) { credit in
                VStack(alignment: .leading, spacing: 4) {
                    Text(credit.title).fontWeight(.medium)
                    Text(credit.subtitle).font(.caption).foregroundStyle(.secondary)
                    if let license = credit.license {
                        Text(license).font(.caption).foregroundStyle(.secondary)
                    }
                    Link(credit.linkTitle, destination: credit.url).font(.caption)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - iCloud toggle

    private func toggleICloud(enable: Bool) {
        let sync = ICloudSyncService.shared
        iCloudMigrationProgress = 0
        iCloudError = nil

        Task {
            do {
                let operation = enable ? sync.enable : sync.disable
                try await operation { progress in
                    Task { @MainActor in iCloudMigrationProgress = progress }
                }
                iCloudEnabled = enable
                iCloudMigrationProgress = nil
            } catch {
                iCloudError = error.localizedDescription
                iCloudMigrationProgress = nil
            }
        }
    }
}
#endif
