import SwiftUI

#if os(macOS)
// Lets callers request a specific tab when opening the settings window (e.g. the
// missing-API-key prompts). The plain Window scene can't carry a value, so this
// singleton bridges the request to the already-mounted SettingsView.
@MainActor
@Observable
final class SettingsWindowNavigation {
    static let shared = SettingsWindowNavigation()
    var requestedSection: SettingsView.SettingsSection?
    private init() {}
}

extension SettingsView {
    enum SettingsSection: String, CaseIterable, Identifiable {
        case general, export, appStoreConnect, googlePlay, automation, beta, purchase, attributions, about

        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .export: "Export"
            case .appStoreConnect: "App Store Connect"
            case .googlePlay: "Google Play"
            case .automation: "Automation"
            case .beta: "Beta"
            case .purchase: "Purchase"
            case .attributions: "Attributions"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .general: "gearshape"
            case .export: "square.and.arrow.up"
            case .appStoreConnect: "arrow.up.circle"
            case .googlePlay: "play.rectangle.on.rectangle"
            case .automation: "terminal"
            case .beta: "flask"
            case .purchase: "star"
            case .attributions: "heart"
            case .about: "info.circle"
            }
        }

        /// The Help topic that documents this pane, so the pane doesn't have to restate it.
        var helpTopic: HelpSection {
            switch self {
            case .general: .settings
            case .export: .exporting
            case .appStoreConnect: .appStoreConnect
            case .googlePlay: .googlePlay
            case .automation: .automation
            case .beta: .settings
            case .purchase: .proFeatures
            case .attributions: .settings
            case .about: .support
            }
        }
    }
}
#endif
