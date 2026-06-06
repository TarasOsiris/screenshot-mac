#if os(iOS)
import SwiftUI

enum iPadRootTab: Hashable {
    case projects
    case settings
}

enum iPadSettingsDestination: Hashable {
    case appStoreConnect
}

@MainActor
@Observable
final class AppNavigationRouter {
    var selectedTab: iPadRootTab = .projects
    var settingsPath: [iPadSettingsDestination] = []

    func openAppStoreConnectSettings() {
        selectedTab = .settings
        settingsPath = [.appStoreConnect]
    }
}
#endif
