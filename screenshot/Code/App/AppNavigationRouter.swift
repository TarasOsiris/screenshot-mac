#if os(iOS)
import SwiftUI

enum iPadRootTab: Hashable {
    case projects
    case settings
}

enum iPadSettingsDestination: Hashable {
    case appStoreConnect
    case googlePlay
}

@MainActor
@Observable
final class AppNavigationRouter {
    var selectedTab: iPadRootTab = .projects
    var settingsPath: [iPadSettingsDestination] = []

    func openStoreSettings(_ destination: iPadSettingsDestination) {
        selectedTab = .settings
        // Seeding settingsPath in the same tick as first-mounting the Settings tab's
        // NavigationStack loses the pushed destination's content (title renders, body doesn't) —
        // give the stack a runloop turn to mount before pushing onto it.
        Task { @MainActor in
            settingsPath = [destination]
        }
    }

    func openAppStoreConnectSettings() {
        openStoreSettings(.appStoreConnect)
    }
}
#endif
