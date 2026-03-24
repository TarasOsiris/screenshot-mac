import SwiftUI

struct SettingsView: View {
    @Environment(StoreService.self) private var store
    @AppStorage("appearance") private var appearance = "auto"
    @AppStorage("defaultScreenshotSize") private var defaultScreenshotSize = "1242x2688"
    @AppStorage("exportFormat") private var exportFormat = "png"
    @AppStorage("openExportFolderOnSuccess") private var openExportFolderOnSuccess = true
    @AppStorage("defaultTemplateCount") private var defaultTemplateCount = 3
    @AppStorage("defaultZoomLevel") private var defaultZoomLevel = 1.0
    @AppStorage("confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("defaultDeviceCategory") private var defaultDeviceCategoryRaw = "iphone"
    @AppStorage("defaultDeviceFrameId") private var defaultDeviceFrameId = ""
    @AppStorage("projectSortOrder") private var projectSortOrder = "creation"

    @State private var iCloudEnabled = ICloudSyncService.shared.isEnabled
    @State private var iCloudAvailable = ICloudSyncService.shared.isAvailable
    @State private var showEnableConfirmation = false
    @State private var showDisableConfirmation = false
    @State private var iCloudMigrationProgress: Double?
    @State private var iCloudError: String?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                generalSettings
            }

            Tab("Export", systemImage: "square.and.arrow.up") {
                exportSettings
            }

            Tab("Purchase", systemImage: "star") {
                purchaseSettings
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

            ScreenshotSizePicker(selection: $defaultScreenshotSize)

            DefaultDevicePicker(categoryRaw: $defaultDeviceCategoryRaw, frameId: $defaultDeviceFrameId)

            TemplateCountPicker(selection: $defaultTemplateCount)

            Toggle("Ask before deleting rows and screenshots", isOn: $confirmBeforeDeleting)

            Picker("Project order", selection: $projectSortOrder) {
                Text("By creation date").tag("creation")
                Text("Alphabetically").tag("alphabetical")
            }

            Picker("Default zoom level", selection: $defaultZoomLevel) {
                Text("50%").tag(0.50)
                Text("75%").tag(0.75)
                Text("100%").tag(1.0)
                Text("125%").tag(1.25)
                Text("150%").tag(1.50)
                Text("175%").tag(1.75)
                Text("200%").tag(2.0)
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

            LabeledContent("Project storage") {
                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([PersistenceService.rootURL])
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
            Picker("Format", selection: $exportFormat) {
                Text("PNG").tag("png")
                Text("JPEG").tag("jpeg")
            }

            Toggle("Reveal in Finder after export", isOn: $openExportFolderOnSuccess)
        }
        .formStyle(.grouped)
    }

    private var purchaseSettings: some View {
        Form {
            Section {
                LabeledContent("Plan") {
                    if store.isProUnlocked {
                        Label("Pro", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Free")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Purchase type") {
                    Text("One-time in-app purchase")
                        .foregroundStyle(.secondary)
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

    @ViewBuilder
    private var freeTierSections: some View {
        Section("Compare Plans") {
            comparisonRow(
                title: "Projects",
                freeValue: "1",
                proValue: "Unlimited"
            )
            comparisonRow(
                title: "Rows per project",
                freeValue: "\(StoreService.freeMaxRows)",
                proValue: "Unlimited"
            )
            comparisonRow(
                title: "Screenshots per row",
                freeValue: "\(StoreService.freeMaxTemplatesPerRow)",
                proValue: "Unlimited"
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

    private func proFeatureRow(_ text: String) -> some View {
        Label(text, systemImage: "checkmark")
            .foregroundStyle(.primary)
    }

    private func comparisonRow(title: String, freeValue: String, proValue: String) -> some View {
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
