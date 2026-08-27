import SwiftUI

#if os(macOS)
struct HelpEntry {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let blocks: [HelpBlock]
}
#endif
