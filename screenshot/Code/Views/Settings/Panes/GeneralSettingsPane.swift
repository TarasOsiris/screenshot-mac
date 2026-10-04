import SwiftUI

#if os(macOS)
struct GeneralSettingsPane: View {
    /// Owned by `SettingsView`: as this pane's `@State`, its file-system-touching init would rerun on every pane init.
    let iCloud: ICloudSettingsModel

    @Environment(PurchaseService.self) private var store
    @Environment(AppState.self) private var appState
    @AppStorage(AppSettingsKeys.appearance) private var appearance = AppSettingsKeys.Default.appearance
    @AppStorage(AppSettingsKeys.appLanguageOverride) private var languageOverride = ""
    @AppStorage(AppSettingsKeys.defaultScreenshotSize) private var defaultScreenshotSize = AppSettingsKeys.Default.defaultScreenshotSize
    @AppStorage(AppSettingsKeys.defaultTemplateCount) private var defaultTemplateCount = AppSettingsKeys.Default.defaultTemplateCount
    @AppStorage(AppSettingsKeys.defaultZoomLevel) private var defaultZoomLevel = AppSettingsKeys.Default.defaultZoomLevel
    @AppStorage(AppSettingsKeys.confirmBeforeDeleting) private var confirmBeforeDeleting = AppSettingsKeys.Default.confirmBeforeDeleting
    @AppStorage(AppSettingsKeys.defaultDeviceCategory) private var defaultDeviceCategoryRaw = AppSettingsKeys.Default.defaultDeviceCategory
    @AppStorage(AppSettingsKeys.defaultDeviceFrameId) private var defaultDeviceFrameId = ""
    @AppStorage(AppSettingsKeys.projectSortOrder) private var projectSortOrder = AppSettingsKeys.Default.projectSortOrder
    @AppStorage(AppSettingsKeys.selectionInspector) private var isSelectionInspectorEnabled = AppSettingsKeys.Default.selectionInspector

    @State private var copiedDiagnostics = false
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false
    @State private var isBackingUp = false
    @State private var backupResult: BackupResult?

    enum BackupResult { case success; case failure(String) }

    var body: some View {
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

            Section {
                Toggle("Edit selected shapes in the inspector", isOn: $isSelectionInspectorEnabled)
            } footer: {
                Text("Shape properties move from the bar below the canvas into the sidebar, and come back to the bar while the sidebar is hidden. Click the row name or press Esc to return to row settings.")
                    .foregroundStyle(.secondary)
            }
            Section("iCloud Sync") {
                ICloudSyncSettingsRows(iCloud: iCloud) { enable in
                    if enable { showEnableConfirmation = true } else { showDisableConfirmation = true }
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
#endif
