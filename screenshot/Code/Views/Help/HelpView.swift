import SwiftUI

#if os(macOS)
struct HelpView: View {
    static let windowID = "help"

    @State private var selection: HelpSection = .welcome

    var body: some View {
        NavigationSplitView {
            List(HelpSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ScrollView {
                detailContent
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.platformTextBackground)
        }
        .navigationTitle("Screenshot Bro Help")
        .frame(minWidth: 880, minHeight: 600)
        .background(WindowSceneBridge(role: .help))
        .screenView(.help)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selection {
        // The only bespoke page: its rows are key caps, not prose blocks.
        case .shortcuts: ShortcutsHelp()
        default: HelpEntryView(entry: selection.entry)
        }
    }
}
#endif
