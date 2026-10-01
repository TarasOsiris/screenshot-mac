#if DIRECT_DISTRIBUTION
import Sparkle
import SwiftUI

/// Sparkle auto-update for the Developer ID build; the feed URL and EdDSA key live in
/// `ScreenshotBro-Direct-Info.plist`.
@MainActor
@Observable
final class DirectUpdater {
    static let shared = DirectUpdater()

    @ObservationIgnored private let controller: SPUStandardUpdaterController

    /// Mirrors Sparkle's own persisted preference, which `SUEnableAutomaticChecks` defaults to on.
    var automaticallyChecksForUpdates: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    private init() {
        // Debug builds share the bundle id but must never replace themselves with a release.
        #if DEBUG
        let startsUpdater = false
        #else
        let startsUpdater = !PersistenceService.isRunningUnderXCTest
        #endif
        controller = SPUStandardUpdaterController(
            startingUpdater: startsUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesCommands: Commands {
    let updater: DirectUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
        }
    }
}

/// Settings ▸ About on the direct build; the App Store build updates through the App Store.
struct DirectUpdateSettingsSection: View {
    @Bindable var updater = DirectUpdater.shared

    var body: some View {
        Section("Updates") {
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecksForUpdates)
            LabeledContent("Software update") {
                Button("Check for Updates…") { updater.checkForUpdates() }
            }
        }
    }
}
#endif
