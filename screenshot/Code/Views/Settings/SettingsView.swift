import SwiftUI

// Settings UI lives in a plain Window scene (the Settings scene is non-resizable on
// macOS 26); an iPad settings surface is a follow-up.
#if os(macOS)
struct SettingsView: View {
    static let windowID = "settings"

    @State private var selection: SettingsSection? = .general
    @State private var iCloud = ICloudSettingsModel()

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(UIMetrics.Window.settingsSidebarWidth)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detailContent
                .navigationTitle((selection ?? .general).title)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        HelpTopicButton(section: (selection ?? .general).helpTopic)
                    }
                }
        }
        .frame(
            minWidth: UIMetrics.Window.settingsMinSize.width,
            idealWidth: UIMetrics.Window.settings.width,
            maxWidth: .infinity,
            minHeight: UIMetrics.Window.settingsMinSize.height,
            idealHeight: UIMetrics.Window.settings.height,
            maxHeight: .infinity
        )
        .background(WindowSceneBridge(role: .settings))
        .screenView(.settings)
        .onAppear(perform: applyRequestedSection)
        .onChange(of: SettingsWindowNavigation.shared.requestedSection) { _, _ in
            applyRequestedSection()
        }
    }

    private func applyRequestedSection() {
        guard let requested = SettingsWindowNavigation.shared.requestedSection else { return }
        selection = requested
        SettingsWindowNavigation.shared.requestedSection = nil
    }

    // Keep every pane mounted and toggle visibility rather than switching (which would rebuild the
    // selected pane on each navigation, discarding transient @State like a shown "Connection
    // succeeded" result or an in-flight test spinner in the App Store Connect / Google Play panes).
    private var detailContent: some View {
        let active = selection ?? .general
        return ZStack {
            ForEach(SettingsSection.allCases) { section in
                detailView(for: section)
                    .opacity(section == active ? 1 : 0)
                    .allowsHitTesting(section == active)
                    .accessibilityHidden(section != active)
            }
        }
    }

    @ViewBuilder
    private func detailView(for section: SettingsSection) -> some View {
        switch section {
        case .general: GeneralSettingsPane(iCloud: iCloud)
        case .export: ExportSettingsPane()
        case .appStoreConnect: AppStoreConnectSettingsView()
        case .googlePlay: GooglePlaySettingsView()
        case .automation: AutomationSettingsPane()
        case .beta: Form { BetaSettingsSection(showsHeader: false) }.formStyle(.grouped)
        case .purchase: PurchaseSettingsPane()
        case .attributions: AttributionsSettingsPane()
        case .about: AboutSettingsPane(isVisible: selection == .about)
        }
    }
}

#Preview {
    let state = AppState()
    SettingsView()
        .environment(PurchaseService())
        .environment(state)
        .environment(state.iCloudStatus)
        .environment(MCPServerService())
}
#endif
