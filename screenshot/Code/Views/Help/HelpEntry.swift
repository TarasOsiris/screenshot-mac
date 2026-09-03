import SwiftUI

#if os(macOS)
struct HelpEntry {
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?
    let blocks: [HelpBlock]
    /// Related topics, rendered as links under the entry. A field rather than a trailing block:
    /// every entry put it last anyway, and this keeps the cross-link map in one greppable place.
    let seeAlso: [HelpSection]

    init(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource? = nil,
        blocks: [HelpBlock],
        seeAlso: [HelpSection] = []
    ) {
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.seeAlso = seeAlso
    }
}
#endif
