import SwiftUI

#if os(macOS)
struct HelpView: View {
    static let windowID = "help"

    @State private var selection: HelpSection = .welcome
    @State private var query = ""

    var body: some View {
        // Trimmed and filtered once per pass: the sidebar list, its empty-state overlay and the
        // selection fixup all read the same values.
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = HelpSection.matching(needle)

        NavigationSplitView {
            sidebar(results)
        } detail: {
            detail(needle)
        }
        .navigationTitle("Screenshot Bro Help")
        .frame(minWidth: 880, minHeight: 600)
        .background(WindowSceneBridge(role: .help))
        .screenView(.help)
        .environment(\.helpSearchQuery, needle)
        .environment(\.openHelpSection) { selection = $0 }
        .onAppear(perform: applyRequestedSection)
        .onChange(of: HelpWindowNavigation.shared.requestedSection) { _, _ in
            applyRequestedSection()
        }
        .onChange(of: results) { _, newResults in
            // Land on something that actually matched, so a search needs no second click.
            if let first = newResults.first, !newResults.contains(selection) { selection = first }
        }
    }

    private func sidebar(_ results: [HelpSection]) -> some View {
        List(results, selection: $selection) { section in
            section.label.tag(section)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        .searchable(text: $query, placement: .sidebar, prompt: Text("Search Help"))
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    private func detail(_ needle: String) -> some View {
        // Derived rather than event-driven: one target, so a keystroke that also moves the
        // selection can't fire two competing scroll animations.
        let target = selection.firstMatchingBlockIndex(needle).map(HelpBlockAnchor.init)

        return ScrollViewReader { proxy in
            ScrollView {
                HelpEntryView(entry: selection.entry)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color.platformTextBackground)
            .onChange(of: target) { _, newTarget in
                guard let newTarget else { return }
                withAnimation { proxy.scrollTo(newTarget, anchor: .center) }
            }
        }
    }

    private func applyRequestedSection() {
        guard let requested = HelpWindowNavigation.shared.requestedSection else { return }
        // A stale query would filter the requested topic straight out of the sidebar.
        query = ""
        selection = requested
        HelpWindowNavigation.shared.requestedSection = nil
    }
}
#endif
