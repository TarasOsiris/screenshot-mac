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
        settingsPath = [destination]
    }

    func openAppStoreConnectSettings() {
        openStoreSettings(.appStoreConnect)
    }
}
#endif
