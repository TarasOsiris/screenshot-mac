import SwiftUI

#if os(macOS)
extension HelpSection {
    /// Resolved once: the UI language only changes across a relaunch, and re-resolving 470-odd
    /// strings per keystroke is exactly what this index exists to avoid. Block texts are kept
    /// alongside so `firstMatchingBlockIndex` doesn't re-resolve them either.
    private static let index: [(section: HelpSection, text: String, blockTexts: [String])] =
        allCases.map { section in
            let entry = section.entry
            var parts = [section.title.helpResolved, entry.title.helpResolved]
            if let subtitle = entry.subtitle { parts.append(subtitle.helpResolved) }
            let blockTexts = entry.blocks.map(\.searchText)
            parts.append(contentsOf: blockTexts)
            return (section, parts.joined(separator: "\n"), blockTexts)
        }

    /// `needle` is already trimmed by the caller.
    static func matching(_ needle: String) -> [HelpSection] {
        guard !needle.isEmpty else { return allCases }
        return index.filter { HelpSearch.matches($0.text, needle) }.map(\.section)
    }

    /// Index of the first block matching `needle`, for scrolling the detail pane to it.
    func firstMatchingBlockIndex(_ needle: String) -> Int? {
        guard !needle.isEmpty,
              let entry = Self.index.first(where: { $0.section == self }) else { return nil }
        return entry.blockTexts.firstIndex { HelpSearch.matches($0, needle) }
    }
}
#endif
