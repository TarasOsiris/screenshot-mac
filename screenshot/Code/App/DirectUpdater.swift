#if DIRECT_DISTRIBUTION
import Sparkle
import SwiftUI

/// Sparkle auto-update for the Developer ID build; the feed URL and EdDSA key live in
/// `ScreenshotBro-Direct-Info.plist`.
@MainActor
final class DirectUpdater {
    private let controller: SPUStandardUpdaterController

    init() {
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
#endif
