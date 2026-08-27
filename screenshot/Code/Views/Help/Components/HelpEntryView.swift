import SwiftUI

#if os(macOS)
struct HelpEntryView: View {
    let entry: HelpEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HelpHeader(entry.title, subtitle: entry.subtitle)
            ForEach(Array(entry.blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let text): HelpHeading(text)
                case .paragraph(let text): HelpParagraph(text)
                case .bullet(let text): HelpBullet(text)
                case .tip(let text): HelpTip(text)
                }
            }
        }
    }
}
#endif
