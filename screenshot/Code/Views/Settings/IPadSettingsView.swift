#if os(iOS)
import SwiftUI

/// iPad Settings surface — the relevant subset of the macOS Settings scene, presented as a
/// grouped Form inside the Settings tab. macOS-only features (Finder reveal, zip backup,
/// export-folder bookmark) are omitted; App Store Connect credentials are reachable via a
/// pushed detail screen.
struct IPadSettingsView: View {
    @Environment(PurchaseService.self) private var store
    @AppStorage(AppSettingsKeys.appearance) private var appearance = AppSettingsKeys.Default.appearance
    @AppStorage(AppSettingsKeys.appLanguageOverride) private var languageOverride = ""
    @AppStorage(AppSettingsKeys.defaultScreenshotSize) private var defaultScreenshotSize = AppSettingsKeys.Default.defaultScreenshotSize
    @AppStorage(AppSettingsKeys.exportFormat) private var exportFormat = AppSettingsKeys.Default.exportFormat
    @AppStorage(AppSettingsKeys.exportCustomSuffix) private var exportCustomSuffix = ""
    @AppStorage(AppSettingsKeys.defaultTemplateCount) private var defaultTemplateCount = AppSettingsKeys.Default.defaultTemplateCount
    @AppStorage(AppSettingsKeys.defaultZoomLevel) private var defaultZoomLevel = AppSettingsKeys.Default.defaultZoomLevel
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) private var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @AppStorage(AppSettingsKeys.defaultDeviceCategory) private var defaultDeviceCategoryRaw = AppSettingsKeys.Default.defaultDeviceCategory
    @AppStorage(AppSettingsKeys.defaultDeviceFrameId) private var defaultDeviceFrameId = ""
    @AppStorage(AppSettingsKeys.projectSortOrder) private var projectSortOrder = AppSettingsKeys.Default.projectSortOrder

    @State private var iCloud = ICloudSettingsModel()
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false

    var body: some View {
        Form {
            if !store.isProUnlocked {
                proUpsellSection
            }
            appearanceSection
            defaultsSection
            editingSection
            exportSection
            appStoreConnectSection
            googlePlaySection
            iCloudSection
            BetaSettingsSection()
            purchaseSection
            legalSection
            attributionsSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .screenView(.settings)
        // The Settings tab is long-lived inside the TabView, and ICloudSyncService isn't
        // @Observable — so re-read its state whenever the tab reappears or sync flips.
        .onAppear(perform: refreshICloudState)
        .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncDidEnable)) { _ in refreshICloudState() }
        .onReceive(NotificationCenter.default.publisher(for: .iCloudSyncDidDisable)) { _ in refreshICloudState() }
        // Attached to the Form (not the iCloud Section): presentation modifiers on a Section
        // inside a Form render a phantom full-height empty block.
        .alert("Enable iCloud Sync", isPresented: $showEnableConfirmation) {
            Button("Enable iCloud Sync") { iCloud.toggle(enable: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All projects will be copied to iCloud. Initial sync may take time for large projects.")
        }
        .confirmationDialog("Disable iCloud Sync", isPresented: $showDisableConfirmation, titleVisibility: .visible) {
            Button("Disable iCloud Sync", role: .destructive) { iCloud.toggle(enable: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Projects will be kept locally. Other devices will no longer see updates.")
        }
    }

    private func refreshICloudState() {
        iCloud.refresh()
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
            AppLanguagePicker(languageOverride: $languageOverride)
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
                .submitLabel(.done)
        } header: {
            Text("Export")
        } footer: {
            let suffixPart = ExportFileNaming.formattedFileSuffix(exportCustomSuffix)
            let ext = (ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png).fileExtension
            Text("Example: 01_Onboarding_en\(suffixPart).\(ext)")
        }
    }

    // MARK: - App Store Connect

    private var appStoreConnectSection: some View {
        Section {
            NavigationLink(value: iPadSettingsDestination.appStoreConnect) {
                Label("App Store Connect", systemImage: "arrow.up.circle")
            }
        }
    }

    private var googlePlaySection: some View {
        Section {
            NavigationLink(value: iPadSettingsDestination.googlePlay) {
                Label("Google Play", systemImage: "play.rectangle.on.rectangle")
            }
        }
    }

    // MARK: - iCloud

    @ViewBuilder
    private var iCloudSection: some View {
        Section("iCloud Sync") {
            ICloudSyncSettingsRows(iCloud: iCloud) { enable in
                if enable { showEnableConfirmation = true } else { showDisableConfirmation = true }
            }
        }
    }

    // MARK: - Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        Section("Purchase") {
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
                    Text("Free").foregroundStyle(.secondary)
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
                ProFeatureRow(text: "Unlimited projects")
                ProFeatureRow(text: "Unlimited rows per project")
                ProFeatureRow(text: "Unlimited screenshots per row")
            }
        } else {
            FreeTierSections(store: store)
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
                AttributionRow(credit: credit)
            }
        }
    }

    @ViewBuilder
    private var aboutSection: some View {
        Section {
            LabeledContent("Version") {
                Text("\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber))")
                    .foregroundStyle(.secondary)
            }
            AboutLinkRows()
            SocialLinkButtons()
                .frame(maxWidth: .infinity)
        }
        MoreAppsSection()
    }

    // MARK: - iCloud toggle

}
#endif
