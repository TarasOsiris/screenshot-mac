import SwiftUI

// The macOS and iPad settings screens are different shells — a NavigationSplitView with a sidebar
// against a single Form — but roughly 60% of what they showed was the same code, forked. The fork
// had already cost a feature: only the iPad status label showed iCloud transfer progress.
//
// What lives here is what both shells present identically. Layout that is genuinely per-platform
// (the sidebar, the MCP automation pane, the backup button) stays in the two views.

/// Every preference key with its default, declared once. Both settings screens plus ContentView
/// used to re-declare the same `@AppStorage` keys with hand-copied defaults, so a changed default
/// silently disagreed with itself depending on which screen wrote it first.
enum AppSettingsKeys {
    static let appearance = "appearance"
    static let appLanguageOverride = "appLanguageOverride"
    static let defaultScreenshotSize = "defaultScreenshotSize"
    static let exportFormat = "exportFormat"
    static let exportCustomSuffix = "exportCustomSuffix"
    static let openExportFolderOnSuccess = "openExportFolderOnSuccess"
    static let defaultTemplateCount = "defaultTemplateCount"
    static let defaultZoomLevel = "defaultZoomLevel"
    static let confirmBeforeDeleting = "confirmBeforeDeleting"
    static let defaultDeviceCategory = "defaultDeviceCategory"
    static let defaultDeviceFrameId = "defaultDeviceFrameId"
    static let projectSortOrder = "projectSortOrder"

    enum Default {
        static let appearance = "auto"
        static let defaultScreenshotSize = "1242x2688"
        static let exportFormat = "png"
        static let defaultTemplateCount = 3
        static let defaultZoomLevel = 1.0
        static let confirmBeforeDeleting = true
        static let openExportFolderOnSuccess = true
        static let defaultDeviceCategory = "iphone"
        static let projectSortOrder = "creation"
    }
}

/// Drives the iCloud toggle: the migration is long-running and reports progress, so both screens
/// need the same four pieces of state and the same enable/disable task.
@MainActor
@Observable
final class ICloudSettingsModel {
    var isEnabled: Bool
    private(set) var isAvailable: Bool
    private(set) var migrationProgress: Double?
    var errorMessage: String?

    init() {
        isEnabled = ICloudSyncService.shared.isEnabled
        isAvailable = ICloudSyncService.shared.isAvailable
    }

    var isMigrating: Bool { migrationProgress != nil }

    func refresh() {
        isEnabled = ICloudSyncService.shared.isEnabled
        isAvailable = ICloudSyncService.shared.isAvailable
    }

    func toggle(enable: Bool) {
        let sync = ICloudSyncService.shared
        migrationProgress = 0
        errorMessage = nil

        Task {
            do {
                let operation = enable ? sync.enable : sync.disable
                try await operation { progress in
                    Task { @MainActor in self.migrationProgress = progress }
                }
                isEnabled = enable
            } catch {
                errorMessage = error.localizedDescription
            }
            migrationProgress = nil
        }
    }
}

/// Live iCloud state, including in-flight transfer progress. macOS used to show only
/// connected/connecting because its copy predated the progress states.
struct ICloudStatusLabel: View {
    let syncStatus: SyncStatus

    var body: some View {
        if !ICloudSyncService.shared.isUsingICloud {
            Label("Connecting...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else {
            switch syncStatus {
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
}

struct PlanDetailRows: View {
    let tier: StoreService.ProTier

    var body: some View {
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
}

/// The compare-plans + upgrade pair shown to users who haven't bought Pro.
struct FreeTierSections: View {
    let store: StoreService

    var body: some View {
        Section("Compare Plans") {
            PlanComparisonRow(title: "Projects", freeValue: "1", proValue: String(localized: "Unlimited"))
            PlanComparisonRow(
                title: "Rows per project",
                freeValue: "\(StoreService.freeMaxRows)",
                proValue: String(localized: "Unlimited")
            )
            PlanComparisonRow(
                title: "Screenshots per row",
                freeValue: "\(StoreService.freeMaxTemplatesPerRow)",
                proValue: String(localized: "Unlimited")
            )
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
}

struct PlanComparisonRow: View {
    let title: LocalizedStringKey
    let freeValue: String
    let proValue: String

    var body: some View {
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

struct ProFeatureRow: View {
    let text: LocalizedStringKey

    var body: some View {
        Label(text, systemImage: "checkmark")
            #if os(iOS)
            // Span the row separator full-width instead of letting iOS indent it past the
            // checkmark icon, which left ragged half-width lines between the feature rows.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            #endif
    }
}

/// The language picker plus the "you have to restart" follow-up. macOS can relaunch itself;
/// iPad can only ask, which is the one real difference between the two.
struct AppLanguagePicker: View {
    @Binding var languageOverride: String
    @State private var showRestartAlert = false

    var body: some View {
        Picker("Language", selection: $languageOverride) {
            Text("System").tag("")
            ForEach(AppLanguageOptions.available, id: \.self) { code in
                Text(AppLanguageOptions.displayName(for: code)).tag(code)
            }
        }
        .onChange(of: languageOverride) { _, newValue in
            AppLanguageOptions.apply(newValue)
            showRestartAlert = true
        }
        .alert("Restart to change language", isPresented: $showRestartAlert) {
            #if os(macOS)
            Button("Restart Now") { relaunchApp() }
            Button("Later", role: .cancel) {}
            #else
            Button("OK", role: .cancel) {}
            #endif
        } message: {
            #if os(macOS)
            Text("The interface language will switch the next time Screenshot Bro launches.")
            #else
            Text("Quit and reopen Screenshot Bro to switch the interface language.")
            #endif
        }
    }

    #if os(macOS)
    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
    #endif
}
