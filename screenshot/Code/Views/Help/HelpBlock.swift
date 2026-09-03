import SwiftUI

#if os(macOS)
enum HelpBlock {
    case heading(LocalizedStringResource)
    case paragraph(LocalizedStringResource)
    case bullet(LocalizedStringResource)
    case tip(LocalizedStringResource)
    /// Key caps rather than prose. A block case rather than a bespoke page, so the shortcuts
    /// topic is searchable and scroll-to-match works there like everywhere else.
    case shortcutRows([ShortcutRowItem])

    var searchText: String {
        switch self {
        case .heading(let text), .paragraph(let text), .bullet(let text), .tip(let text):
            text.helpResolved
        case .shortcutRows(let rows):
            rows.map { "\($0.keys) \($0.description.helpResolved)" }.joined(separator: "\n")
        }
    }
}

struct ShortcutRowItem {
    let keys: String
    let description: LocalizedStringResource
}
#endif
