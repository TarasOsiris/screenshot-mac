import SwiftUI

#if os(macOS)
struct HelpEntryView: View {
    let entry: HelpEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpHeader(entry.title, subtitle: entry.subtitle)
            ForEach(Array(entry.blocks.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .id(HelpBlockAnchor(index: index))
            }
            if !entry.seeAlso.isEmpty {
                HelpSeeAlso(sections: entry.seeAlso)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: HelpBlock) -> some View {
        switch block {
        case .heading(let text): HelpHeading(text)
        case .paragraph(let text): HelpParagraph(text)
        case .bullet(let text): HelpBullet(text)
        case .tip(let text): HelpTip(text)
        case .shortcutRows(let rows):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    ShortcutRow(item: row)
                }
            }
        }
    }
}

/// Scroll target for "jump to the first block matching the search".
struct HelpBlockAnchor: Hashable {
    let index: Int
}
#endif
