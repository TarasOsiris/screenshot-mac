import SwiftUI

#if os(macOS)
/// Lets callers open Help at a specific topic. Mirrors `SettingsWindowNavigation`: the plain
/// `Window` scene can't carry a value, so this singleton bridges the request to the mounted view.
@MainActor
@Observable
final class HelpWindowNavigation {
    static let shared = HelpWindowNavigation()
    var requestedSection: HelpSection?
    private init() {}
}

/// The standard "?" affordance. Put it next to a control whose topic Help already covers, rather
/// than restating that topic in a popover.
struct HelpTopicButton: View {
    let section: HelpSection

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            AppWindowManager.shared.showHelp(section, using: openWindow)
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.borderless)
        .focusable(false)
        .help(Text("Open Help"))
        .accessibilityLabel(Text("Open Help"))
    }
}
#endif
